package servicerecord

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"
	_ "time/tzdata" // the runtime image ships no zoneinfo

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"mototeca-backend/internal/auth"
	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
	"mototeca-backend/internal/vehicle"
)

// Dashboard page size when the client doesn't ask for one, and the ceiling it
// cannot exceed however large a limit it sends.
const (
	defaultListLimit = 50
	maxListLimit     = 100
)

type Handler struct {
	repo   Store
	logger *slog.Logger
}

func NewHandler(repo Store, logger *slog.Logger) *Handler {
	return &Handler{repo: repo, logger: logger}
}

func (h *Handler) CreateServiceRecord(ctx context.Context, req *connect.Request[servicev1.CreateServiceRecordRequest]) (*connect.Response[servicev1.CreateServiceRecordResponse], error) {
	workshopID, err := auth.RequireWorkshopID(ctx)
	if err != nil {
		return nil, err
	}

	input := CreateInput{
		WorkshopID:   workshopID,
		Plate:        vehicle.NormalizePlate(req.Msg.Plate),
		MechanicName: req.Msg.MechanicName,
		Operations:   operationsFromProto(req.Msg.Operations),
		MileageKm:    int(req.Msg.MileageKm),
		CostCents:    intPtr(req.Msg.CostCents),
		Notes:        req.Msg.Notes,
		Parts:        partsFromProto(req.Msg.Parts),

		ConfirmLowerMileage: req.Msg.ConfirmLowerMileage,
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	record, err := h.repo.Create(ctx, input)
	if lower, ok := errors.AsType[*LowerMileageError](err); ok {
		return nil, connect.NewError(connect.CodeFailedPrecondition, fmt.Errorf(
			"quilometragem menor que a última registrada para esta moto (%d km)", lower.HighestKm))
	}
	if errors.Is(err, ErrVehicleNotFound) {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("moto não cadastrada — cadastre a placa antes"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "create service record failed", "err", err, "plate", input.Plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao salvar o registro"))
	}

	return connect.NewResponse(&servicev1.CreateServiceRecordResponse{
		Record: ToProto(record),
	}), nil
}

func (h *Handler) ReviseServiceRecord(ctx context.Context, req *connect.Request[servicev1.ReviseServiceRecordRequest]) (*connect.Response[servicev1.ReviseServiceRecordResponse], error) {
	workshopID, err := auth.RequireWorkshopID(ctx)
	if err != nil {
		return nil, err
	}
	if req.Msg.RecordId == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe o registro a corrigir"))
	}

	// The plate is not taken from the request: a correction stays on the same
	// bike as the record it replaces.
	original, err := h.repo.FindByID(ctx, req.Msg.RecordId)
	if err != nil {
		h.logger.ErrorContext(ctx, "loading record to revise failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao corrigir o registro"))
	}
	if original == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("registro não encontrado"))
	}

	input := CreateInput{
		WorkshopID:      workshopID,
		Plate:           original.Vehicle.Plate,
		MechanicName:    req.Msg.MechanicName,
		Operations:      operationsFromProto(req.Msg.Operations),
		MileageKm:       int(req.Msg.MileageKm),
		CostCents:       intPtr(req.Msg.CostCents),
		Notes:           req.Msg.Notes,
		Parts:           partsFromProto(req.Msg.Parts),
		RevisesRecordID: &req.Msg.RecordId,
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	record, err := h.repo.Revise(ctx, workshopID, req.Msg.RecordId, input)
	switch {
	case errors.Is(err, ErrRecordNotFound):
		return nil, connect.NewError(connect.CodeNotFound, errors.New("registro não encontrado"))
	case errors.Is(err, ErrAlreadySuperseded):
		return nil, connect.NewError(connect.CodeFailedPrecondition,
			errors.New("este registro já foi corrigido — revise a correção"))
	case err != nil:
		h.logger.ErrorContext(ctx, "revise service record failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao corrigir o registro"))
	}

	return connect.NewResponse(&servicev1.ReviseServiceRecordResponse{
		Record: ToProto(record),
	}), nil
}

func operationsFromProto(raw []servicev1.ServiceType) []Operation {
	operations := make([]Operation, 0, len(raw))
	for _, op := range raw {
		operations = append(operations, operationFromProto(op))
	}
	return operations
}

func partsFromProto(raw []*servicev1.Part) []Part {
	parts := make([]Part, 0, len(raw))
	for _, p := range raw {
		parts = append(parts, Part{
			Name:      p.Name,
			Quantity:  int(p.Quantity),
			CostCents: intPtr(p.CostCents),
		})
	}
	return parts
}

func (h *Handler) GetServiceRecord(ctx context.Context, req *connect.Request[servicev1.GetServiceRecordRequest]) (*connect.Response[servicev1.GetServiceRecordResponse], error) {
	if req.Msg.Id == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe o registro"))
	}

	record, err := h.repo.FindByID(ctx, req.Msg.Id)
	if err != nil {
		h.logger.ErrorContext(ctx, "get service record failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar o registro"))
	}
	if record == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("registro não encontrado"))
	}

	return connect.NewResponse(&servicev1.GetServiceRecordResponse{
		Record: ToProto(record),
	}), nil
}

func (h *Handler) ListServiceRecordsByPlate(ctx context.Context, req *connect.Request[servicev1.ListServiceRecordsByPlateRequest]) (*connect.Response[servicev1.ListServiceRecordsByPlateResponse], error) {
	plate := vehicle.NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe a placa"))
	}

	summary, records, err := h.repo.ListByPlate(ctx, plate, clampLimit(req.Msg.Limit))
	if err != nil {
		h.logger.ErrorContext(ctx, "list service records by plate failed", "err", err, "plate", plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar o histórico"))
	}
	if summary == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("nenhuma moto cadastrada com esta placa"))
	}

	return connect.NewResponse(&servicev1.ListServiceRecordsByPlateResponse{
		Vehicle: vehicleToProto(*summary),
		Records: recordsToProto(records),
	}), nil
}

func (h *Handler) ListWorkshopServiceRecords(ctx context.Context, req *connect.Request[servicev1.ListWorkshopServiceRecordsRequest]) (*connect.Response[servicev1.ListWorkshopServiceRecordsResponse], error) {
	workshopID, err := auth.RequireWorkshopID(ctx)
	if err != nil {
		return nil, err
	}

	records, err := h.repo.ListByWorkshop(ctx, workshopID, clampLimit(req.Msg.Limit))
	if err != nil {
		h.logger.ErrorContext(ctx, "list workshop service records failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar os registros"))
	}

	startOfMonth := startOfMonth(time.Now())
	count, err := h.repo.CountByWorkshopSince(ctx, workshopID, startOfMonth)
	if err != nil {
		h.logger.ErrorContext(ctx, "counting workshop records this month failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar os registros"))
	}

	return connect.NewResponse(&servicev1.ListWorkshopServiceRecordsResponse{
		Records:        recordsToProto(records),
		CountThisMonth: int32(count),
	}), nil
}

// workshopZone is where "this month" is counted. The server runs in UTC, which
// would move the last evening of each month into the next one.
var workshopZone = mustLoadLocation("America/Sao_Paulo")

func mustLoadLocation(name string) *time.Location {
	location, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return location
}

func startOfMonth(now time.Time) time.Time {
	local := now.In(workshopZone)
	return time.Date(local.Year(), local.Month(), 1, 0, 0, 0, 0, workshopZone)
}

// clampLimit applies the default and the ceiling a client cannot exceed.
func clampLimit(requested int32) int {
	if requested <= 0 {
		return defaultListLimit
	}
	return min(int(requested), maxListLimit)
}

func intPtr(v *int32) *int {
	if v == nil {
		return nil
	}
	converted := int(*v)
	return &converted
}

func int32Ptr(v *int) *int32 {
	if v == nil {
		return nil
	}
	converted := int32(*v)
	return &converted
}

func recordsToProto(records []ServiceRecord) []*servicev1.ServiceRecord {
	out := make([]*servicev1.ServiceRecord, 0, len(records))
	for i := range records {
		out = append(out, ToProto(&records[i]))
	}
	return out
}

// ToProto converts a record to its wire form. Exported because the owner
// domain embeds the last service in "Minhas Motos".
func ToProto(r *ServiceRecord) *servicev1.ServiceRecord {
	operations := make([]servicev1.ServiceType, 0, len(r.Operations))
	for _, op := range r.Operations {
		operations = append(operations, operationToProto(op))
	}

	parts := make([]*servicev1.Part, 0, len(r.Parts))
	for _, p := range r.Parts {
		parts = append(parts, &servicev1.Part{
			Name:      p.Name,
			Quantity:  int32(p.Quantity),
			CostCents: int32Ptr(p.CostCents),
		})
	}

	attachments := make([]*servicev1.Attachment, 0, len(r.Attachments))
	for _, a := range r.Attachments {
		attachments = append(attachments, &servicev1.Attachment{
			Id:    a.ID,
			Url:   a.URL,
			Kind:  a.Kind,
			Phase: phaseToProto(a.Phase),
		})
	}

	return &servicev1.ServiceRecord{
		Id:              r.ID,
		Vehicle:         vehicleToProto(r.Vehicle),
		WorkshopName:    r.WorkshopName,
		MechanicName:    r.MechanicName,
		Operations:      operations,
		MileageKm:       int32(r.MileageKm),
		CostCents:       int32Ptr(r.CostCents),
		Notes:           r.Notes,
		Parts:           parts,
		Attachments:     attachments,
		CreatedAt:       timestamppb.New(r.CreatedAt),
		RevisesRecordId: r.RevisesRecordID,

		SupersededByRecordId: r.SupersededByID,
	}
}

func vehicleToProto(v VehicleSummary) *servicev1.VehicleSummary {
	return &servicev1.VehicleSummary{
		Plate: v.Plate,
		Make:  v.Make,
		Model: v.Model,
		Year:  int32(v.Year),
	}
}

func phaseToProto(phase *string) servicev1.PhotoPhase {
	if phase == nil {
		return servicev1.PhotoPhase_PHOTO_PHASE_UNSPECIFIED
	}
	switch *phase {
	case PhaseBefore:
		return servicev1.PhotoPhase_PHOTO_PHASE_BEFORE
	case PhaseAfter:
		return servicev1.PhotoPhase_PHOTO_PHASE_AFTER
	default:
		return servicev1.PhotoPhase_PHOTO_PHASE_UNSPECIFIED
	}
}

// operationProtoPairs is the single place the wire enum and the database enum
// are tied together, so adding a taxonomy entry means editing one table.
var operationProtoPairs = []struct {
	domain Operation
	proto  servicev1.ServiceType
}{
	{OperationOilChange, servicev1.ServiceType_SERVICE_TYPE_OIL_CHANGE},
	{OperationScheduledReview, servicev1.ServiceType_SERVICE_TYPE_SCHEDULED_REVIEW},
	{OperationBrakes, servicev1.ServiceType_SERVICE_TYPE_BRAKES},
	{OperationChainAndSprocket, servicev1.ServiceType_SERVICE_TYPE_CHAIN_AND_SPROCKET},
	{OperationTires, servicev1.ServiceType_SERVICE_TYPE_TIRES},
	{OperationElectrical, servicev1.ServiceType_SERVICE_TYPE_ELECTRICAL},
	{OperationSparkPlugs, servicev1.ServiceType_SERVICE_TYPE_SPARK_PLUGS},
	{OperationSuspension, servicev1.ServiceType_SERVICE_TYPE_SUSPENSION},
	{OperationClutch, servicev1.ServiceType_SERVICE_TYPE_CLUTCH},
	{OperationFuelInjection, servicev1.ServiceType_SERVICE_TYPE_FUEL_INJECTION},
	{OperationBodywork, servicev1.ServiceType_SERVICE_TYPE_BODYWORK},
	{OperationOther, servicev1.ServiceType_SERVICE_TYPE_OTHER},
}

var (
	operationToProtoMap   = map[Operation]servicev1.ServiceType{}
	operationFromProtoMap = map[servicev1.ServiceType]Operation{}
)

func init() {
	for _, pair := range operationProtoPairs {
		operationToProtoMap[pair.domain] = pair.proto
		operationFromProtoMap[pair.proto] = pair.domain
	}
}

func operationToProto(op Operation) servicev1.ServiceType {
	return operationToProtoMap[op]
}

// operationFromProto returns an empty Operation for an unknown value, which
// Validate then rejects with INVALID_ARGUMENT.
func operationFromProto(t servicev1.ServiceType) Operation {
	return operationFromProtoMap[t]
}
