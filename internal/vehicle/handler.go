package vehicle

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"mototeca-backend/internal/auth"
	vehiclev1 "mototeca-backend/internal/gen/mototeca/vehicle/v1"
)

type Handler struct {
	repo   Store
	logger *slog.Logger
}

func NewHandler(repo Store, logger *slog.Logger) *Handler {
	return &Handler{repo: repo, logger: logger}
}

// GetVehicleByPlate is for the shop about to work on the bike, since it returns
// the chassi. The public lookup is ListServiceRecordsByPlate, which does not.
func (h *Handler) GetVehicleByPlate(ctx context.Context, req *connect.Request[vehiclev1.GetVehicleByPlateRequest]) (*connect.Response[vehiclev1.GetVehicleByPlateResponse], error) {
	if _, err := auth.RequireWorkshopID(ctx); err != nil {
		return nil, err
	}

	plate := NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe a placa"))
	}

	v, err := h.repo.FindByPlate(ctx, plate)
	if err != nil {
		err = fmt.Errorf("finding vehicle by plate %q: %w", plate, err)
		h.logger.ErrorContext(ctx, "get vehicle by plate failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao buscar a moto"))
	}
	if v == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("nenhuma moto cadastrada com esta placa"))
	}

	return connect.NewResponse(&vehiclev1.GetVehicleByPlateResponse{
		Vehicle: toProto(v),
	}), nil
}

// CreateVehicle takes a workshop or an owner session: either may be the first
// to register a bike, and an anonymous caller could squat a plate.
func (h *Handler) CreateVehicle(ctx context.Context, req *connect.Request[vehiclev1.CreateVehicleRequest]) (*connect.Response[vehiclev1.CreateVehicleResponse], error) {
	if _, err := auth.RequireSubject(ctx); err != nil {
		return nil, err
	}

	input := CreateInput{
		Plate:  req.Msg.Plate,
		Chassi: req.Msg.Chassi,
		Make:   req.Msg.Make,
		Model:  req.Msg.Model,
		Year:   int(req.Msg.Year),
	}.Normalized()
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	v, err := h.repo.Create(ctx, input)
	switch {
	case errors.Is(err, ErrDuplicatePlate):
		return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("esta placa já está cadastrada"))
	case errors.Is(err, ErrDuplicateChassi):
		return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("este chassi já está cadastrado em outra placa"))
	case err != nil:
		err = fmt.Errorf("creating vehicle with plate %q: %w", input.Plate, err)
		h.logger.ErrorContext(ctx, "create vehicle failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao cadastrar a moto"))
	}

	return connect.NewResponse(&vehiclev1.CreateVehicleResponse{
		Vehicle: toProto(v),
	}), nil
}

func toProto(v *Vehicle) *vehiclev1.Vehicle {
	return &vehiclev1.Vehicle{
		Id:        v.ID,
		Plate:     v.Plate,
		Chassi:    v.Chassi,
		Make:      v.Make,
		Model:     v.Model,
		Year:      int32(v.Year),
		CreatedAt: timestamppb.New(v.CreatedAt),
	}
}
