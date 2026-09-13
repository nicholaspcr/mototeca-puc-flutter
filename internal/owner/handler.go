package owner

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"mototeca-backend/internal/auth"
	ownerv1 "mototeca-backend/internal/gen/mototeca/owner/v1"
	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/vehicle"
)

// dummyHash makes an unregistered phone cost the same time as a wrong
// password, so Login can't be used to enumerate who has an account.
const dummyHash = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"

type Handler struct {
	repo    Store
	records servicerecord.Store
	signer  *auth.Signer
	logger  *slog.Logger
}

// NewHandler takes the record store too, so "Minhas Motos" can show the last
// service without re-implementing its hydration.
func NewHandler(repo Store, records servicerecord.Store, signer *auth.Signer, logger *slog.Logger) *Handler {
	return &Handler{repo: repo, records: records, signer: signer, logger: logger}
}

func (h *Handler) CreateOwner(ctx context.Context, req *connect.Request[ownerv1.CreateOwnerRequest]) (*connect.Response[ownerv1.CreateOwnerResponse], error) {
	input := CreateInput{
		Name:     req.Msg.Name,
		Phone:    req.Msg.Phone,
		Password: req.Msg.Password,
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	passwordHash, err := auth.HashPassword(input.Password)
	if err != nil {
		h.logger.ErrorContext(ctx, "hashing owner password failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao criar a conta"))
	}

	o, err := h.repo.Create(ctx, input, passwordHash)
	if errors.Is(err, ErrDuplicatePhone) {
		return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("este celular já tem cadastro"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "create owner failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao criar a conta"))
	}

	token, err := h.issueToken(ctx, o.ID)
	if err != nil {
		return nil, err
	}

	return connect.NewResponse(&ownerv1.CreateOwnerResponse{
		Owner: toProto(o),
		Token: token,
	}), nil
}

func (h *Handler) Login(ctx context.Context, req *connect.Request[ownerv1.LoginRequest]) (*connect.Response[ownerv1.LoginResponse], error) {
	// One message for every failure: never reveal whether the phone exists.
	unauthenticated := connect.NewError(connect.CodeUnauthenticated, errors.New("celular ou senha inválidos"))

	phone := NormalizePhone(req.Msg.Phone)
	if phone == "" || req.Msg.Password == "" {
		return nil, unauthenticated
	}

	o, err := h.repo.FindByPhone(ctx, phone)
	if err != nil {
		h.logger.ErrorContext(ctx, "owner login lookup failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao entrar"))
	}

	digest := dummyHash
	if o != nil {
		digest = o.PasswordHash
	}
	if !auth.CheckPassword(digest, req.Msg.Password) || o == nil {
		return nil, unauthenticated
	}

	token, err := h.issueToken(ctx, o.ID)
	if err != nil {
		return nil, err
	}

	return connect.NewResponse(&ownerv1.LoginResponse{
		Owner: toProto(o),
		Token: token,
	}), nil
}

func (h *Handler) ListMyVehicles(ctx context.Context, _ *connect.Request[ownerv1.ListMyVehiclesRequest]) (*connect.Response[ownerv1.ListMyVehiclesResponse], error) {
	ownerID, err := auth.RequireOwnerID(ctx)
	if err != nil {
		return nil, err
	}

	owned, err := h.repo.ListVehicles(ctx, ownerID)
	if err != nil {
		h.logger.ErrorContext(ctx, "listing owner vehicles failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar suas motos"))
	}

	vehicles := make([]*ownerv1.OwnedVehicle, 0, len(owned))
	for _, v := range owned {
		converted, err := h.ownedToProto(ctx, v)
		if err != nil {
			return nil, err
		}
		vehicles = append(vehicles, converted)
	}

	return connect.NewResponse(&ownerv1.ListMyVehiclesResponse{Vehicles: vehicles}), nil
}

func (h *Handler) ClaimVehicle(ctx context.Context, req *connect.Request[ownerv1.ClaimVehicleRequest]) (*connect.Response[ownerv1.ClaimVehicleResponse], error) {
	ownerID, err := auth.RequireOwnerID(ctx)
	if err != nil {
		return nil, err
	}

	plate := vehicle.NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe a placa"))
	}

	owned, err := h.repo.Claim(ctx, ownerID, plate)
	switch {
	case errors.Is(err, ErrVehicleNotFound):
		return nil, connect.NewError(connect.CodeNotFound, errors.New("nenhuma moto cadastrada com esta placa"))
	case errors.Is(err, ErrVehicleClaimed):
		return nil, connect.NewError(connect.CodeFailedPrecondition, errors.New("esta moto já está vinculada a outro proprietário"))
	case err != nil:
		h.logger.ErrorContext(ctx, "claiming vehicle failed", "err", err, "plate", plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao vincular a moto"))
	}

	converted, err := h.ownedToProto(ctx, *owned)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(&ownerv1.ClaimVehicleResponse{Vehicle: converted}), nil
}

func (h *Handler) ReleaseVehicle(ctx context.Context, req *connect.Request[ownerv1.ReleaseVehicleRequest]) (*connect.Response[ownerv1.ReleaseVehicleResponse], error) {
	ownerID, err := auth.RequireOwnerID(ctx)
	if err != nil {
		return nil, err
	}

	plate := vehicle.NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe a placa"))
	}

	err = h.repo.Release(ctx, ownerID, plate)
	if errors.Is(err, ErrVehicleNotFound) {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("esta moto não está vinculada a você"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "releasing vehicle failed", "err", err, "plate", plate)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao desvincular a moto"))
	}

	return connect.NewResponse(&ownerv1.ReleaseVehicleResponse{}), nil
}

func (h *Handler) issueToken(ctx context.Context, ownerID string) (string, error) {
	token, err := h.signer.Issue(auth.Subject{Kind: auth.KindOwner, ID: ownerID}, time.Now())
	if err != nil {
		h.logger.ErrorContext(ctx, "issuing owner token failed", "err", err)
		return "", connect.NewError(connect.CodeInternal, errors.New("falha ao iniciar a sessão"))
	}
	return token, nil
}

func (h *Handler) ownedToProto(ctx context.Context, v OwnedVehicle) (*ownerv1.OwnedVehicle, error) {
	reminder := v.Reminder()

	out := &ownerv1.OwnedVehicle{
		Vehicle: &servicev1.VehicleSummary{
			Plate: v.Vehicle.Plate,
			Make:  v.Vehicle.Make,
			Model: v.Vehicle.Model,
			Year:  int32(v.Vehicle.Year),
		},
		CurrentMileageKm: int32(v.CurrentMileageKm),
		ServiceCount:     int32(v.ServiceCount),
		Reminder:         reminder.Text,
		ReminderIsDue:    reminder.IsDue,
		NextOilChangeKm:  int32(reminder.DueAtKm),
	}

	if reminder.DueAtKm > 0 {
		out.OilChangeIntervalKm = OilChangeIntervalKm
	}

	if v.LastServiceID == nil {
		return out, nil
	}

	record, err := h.records.FindByID(ctx, *v.LastServiceID)
	if err != nil {
		h.logger.ErrorContext(ctx, "loading last service failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao carregar suas motos"))
	}
	if record != nil {
		out.LastService = servicerecord.ToProto(record)
	}
	return out, nil
}

func toProto(o *Owner) *ownerv1.Owner {
	return &ownerv1.Owner{
		Id:        o.ID,
		Name:      o.Name,
		Phone:     o.Phone,
		CreatedAt: timestamppb.New(o.CreatedAt),
	}
}
