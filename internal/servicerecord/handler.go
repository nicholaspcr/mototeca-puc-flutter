package servicerecord

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"mototeca-backend/internal/auth"
	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
	"mototeca-backend/internal/vehicle"
)

// Dashboard page size when the client doesn't ask for one, and the ceiling it
// cannot exceed however large a limit it sends.
const (
	defaultListLimit = 20
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

	operations := make([]Operation, 0, len(req.Msg.Operations))
	for _, op := range req.Msg.Operations {
		operations = append(operations, operationFromProto(op))
	}

	parts := make([]Part, 0, len(req.Msg.Parts))
	for _, p := range req.Msg.Parts {
		parts = append(parts, Part{
			Name:      p.Name,
			Quantity:  int(p.Quantity),
			CostCents: intPtr(p.CostCents),
		})
	}

	input := CreateInput{
		WorkshopID:   workshopID,
		Plate:        vehicle.NormalizePlate(req.Msg.Plate),
		MechanicName: req.Msg.MechanicName,
		Operations:   operations,
		MileageKm:    int(req.Msg.MileageKm),
		CostCents:    intPtr(req.Msg.CostCents),
		Notes:        req.Msg.Notes,
		Parts:        parts,
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	record, err := h.repo.Create(ctx, input)
	if errors.Is(err, ErrVehicleNotFound) {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("vehicle not registered — register the plate first"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "create service record failed", "err", err, "plate", input.Plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to create service record"))
	}

	return connect.NewResponse(&servicev1.CreateServiceRecordResponse{
		Record: toProto(record),
	}), nil
}

func (h *Handler) GetServiceRecord(ctx context.Context, req *connect.Request[servicev1.GetServiceRecordRequest]) (*connect.Response[servicev1.GetServiceRecordResponse], error) {
	if req.Msg.Id == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("id is required"))
	}

	record, err := h.repo.FindByID(ctx, req.Msg.Id)
	if err != nil {
		h.logger.ErrorContext(ctx, "get service record failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to load service record"))
	}
	if record == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("service record not found"))
	}

	return connect.NewResponse(&servicev1.GetServiceRecordResponse{
		Record: toProto(record),
	}), nil
}

func (h *Handler) ListServiceRecordsByPlate(ctx context.Context, req *connect.Request[servicev1.ListServiceRecordsByPlateRequest]) (*connect.Response[servicev1.ListServiceRecordsByPlateResponse], error) {
	plate := vehicle.NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("plate is required"))
	}

	summary, records, err := h.repo.ListByPlate(ctx, plate)
	if err != nil {
		h.logger.ErrorContext(ctx, "list service records by plate failed", "err", err, "plate", plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to load history"))
	}
	if summary == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("no vehicle registered under this plate"))
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

	limit := int(req.Msg.Limit)
	if limit <= 0 {
		limit = defaultListLimit
	}
	limit = min(limit, maxListLimit)

	records, err := h.repo.ListByWorkshop(ctx, workshopID, limit)
	if err != nil {
		h.logger.ErrorContext(ctx, "list workshop service records failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to load records"))
	}

	now := time.Now()
	startOfMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	count, err := h.repo.CountByWorkshopSince(ctx, workshopID, startOfMonth)
	if err != nil {
		h.logger.ErrorContext(ctx, "counting workshop records this month failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to load records"))
	}

	return connect.NewResponse(&servicev1.ListWorkshopServiceRecordsResponse{
		Records:        recordsToProto(records),
		CountThisMonth: int32(count),
	}), nil
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
		out = append(out, toProto(&records[i]))
	}
	return out
}

func toProto(r *ServiceRecord) *servicev1.ServiceRecord {
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
		Id:           r.ID,
		Vehicle:      vehicleToProto(r.Vehicle),
		WorkshopName: r.WorkshopName,
		MechanicName: r.MechanicName,
		Operations:   operations,
		MileageKm:    int32(r.MileageKm),
		CostCents:    int32Ptr(r.CostCents),
		Notes:        r.Notes,
		Parts:        parts,
		Attachments:  attachments,
		CreatedAt:    timestamppb.New(r.CreatedAt),
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
