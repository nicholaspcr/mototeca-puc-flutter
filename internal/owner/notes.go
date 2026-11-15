package owner

import (
	"context"
	"errors"
	"time"

	"connectrpc.com/connect"

	"mototeca-backend/internal/auth"
	ownerv1 "mototeca-backend/internal/gen/mototeca/owner/v1"
	"mototeca-backend/internal/note"
	"mototeca-backend/internal/vehicle"
)

// PhotoRemover deletes a stored photo by URL.
type PhotoRemover interface {
	Delete(ctx context.Context, url string) error
}

func (h *Handler) AddMaintenanceNote(ctx context.Context, req *connect.Request[ownerv1.AddMaintenanceNoteRequest]) (*connect.Response[ownerv1.AddMaintenanceNoteResponse], error) {
	ownerID, err := auth.RequireOwnerID(ctx)
	if err != nil {
		return nil, err
	}

	input := note.AddInput{
		OwnerID:     ownerID,
		Plate:       vehicle.NormalizePlate(req.Msg.Plate),
		ClientID:    req.Msg.ClientId,
		DoneOn:      req.Msg.DoneOn,
		Description: req.Msg.Description,
		MileageKm:   intPtr(req.Msg.MileageKm),
		CostCents:   intPtr(req.Msg.CostCents),
	}
	if input.Plate == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("informe a placa"))
	}
	doneOn, err := input.Validate(time.Now())
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	added, err := h.notes.Add(ctx, input, doneOn)
	if errors.Is(err, note.ErrNotOwned) {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("esta moto não está vinculada a você"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "adding maintenance note failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao publicar a anotação"))
	}

	return connect.NewResponse(&ownerv1.AddMaintenanceNoteResponse{Note: note.ToProto(*added)}), nil
}

func (h *Handler) DeleteMaintenanceNote(ctx context.Context, req *connect.Request[ownerv1.DeleteMaintenanceNoteRequest]) (*connect.Response[ownerv1.DeleteMaintenanceNoteResponse], error) {
	ownerID, err := auth.RequireOwnerID(ctx)
	if err != nil {
		return nil, err
	}

	photoURL, err := h.notes.Delete(ctx, ownerID, req.Msg.Id)
	if errors.Is(err, note.ErrNotFound) {
		return nil, connect.NewError(connect.CodeNotFound, errors.New("anotação não encontrada"))
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "deleting maintenance note failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("falha ao apagar a anotação"))
	}

	// The note is gone either way; a leftover file is only wasted space.
	if photoURL != nil && h.photos != nil {
		if err := h.photos.Delete(context.WithoutCancel(ctx), *photoURL); err != nil {
			h.logger.ErrorContext(ctx, "removing note photo failed", "err", err)
		}
	}

	return connect.NewResponse(&ownerv1.DeleteMaintenanceNoteResponse{}), nil
}

func intPtr(v *int32) *int {
	if v == nil {
		return nil
	}
	i := int(*v)
	return &i
}
