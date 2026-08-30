package vehicle

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	vehiclev1 "mototeca-backend/internal/gen/mototeca/vehicle/v1"
)

type Handler struct {
	repo   Store
	logger *slog.Logger
}

func NewHandler(repo Store, logger *slog.Logger) *Handler {
	return &Handler{repo: repo, logger: logger}
}

func (h *Handler) GetVehicleByPlate(ctx context.Context, req *connect.Request[vehiclev1.GetVehicleByPlateRequest]) (*connect.Response[vehiclev1.GetVehicleByPlateResponse], error) {
	plate := NormalizePlate(req.Msg.Plate)
	if plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("plate is required"))
	}

	v, err := h.repo.FindByPlate(ctx, plate)
	if err != nil {
		err = fmt.Errorf("finding vehicle by plate %q: %w", plate, err)
		h.logger.ErrorContext(ctx, "get vehicle by plate failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to look up vehicle"))
	}
	if v == nil {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("vehicle not found"))
	}

	return connect.NewResponse(&vehiclev1.GetVehicleByPlateResponse{
		Vehicle: toProto(v),
	}), nil
}

func (h *Handler) CreateVehicle(ctx context.Context, req *connect.Request[vehiclev1.CreateVehicleRequest]) (*connect.Response[vehiclev1.CreateVehicleResponse], error) {
	input := CreateInput{
		Plate:  req.Msg.Plate,
		Chassi: req.Msg.Chassi,
		Make:   req.Msg.Make,
		Model:  req.Msg.Model,
		Year:   int(req.Msg.Year),
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	v, err := h.repo.Create(ctx, input)
	if err != nil {
		err = fmt.Errorf("creating vehicle with plate %q: %w", input.Plate, err)
		h.logger.ErrorContext(ctx, "create vehicle failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to create vehicle"))
	}

	return connect.NewResponse(&vehiclev1.CreateVehicleResponse{
		Vehicle: toProto(v),
	}), nil
}

func toProto(v *Vehicle) *vehiclev1.Vehicle {
	out := &vehiclev1.Vehicle{
		Id:        v.ID,
		Plate:     v.Plate,
		Chassi:    v.Chassi,
		Make:      v.Make,
		Model:     v.Model,
		Year:      int32(v.Year),
		CreatedAt: timestamppb.New(v.CreatedAt),
	}
	if v.CurrentOwnerID != nil {
		out.CurrentOwnerId = v.CurrentOwnerID
	}
	return out
}
