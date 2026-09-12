package workshop

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"mototeca-backend/internal/auth"
	workshopv1 "mototeca-backend/internal/gen/mototeca/workshop/v1"
)

// dummyHash is a valid bcrypt digest of a random string. Login compares
// against it when no workshop matches the CNPJ, so an unregistered CNPJ costs
// the same time as a wrong password and the endpoint cannot be used to
// enumerate which shops are registered.
const dummyHash = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"

type Handler struct {
	repo   Store
	signer *auth.Signer
	logger *slog.Logger
}

func NewHandler(repo Store, signer *auth.Signer, logger *slog.Logger) *Handler {
	return &Handler{repo: repo, signer: signer, logger: logger}
}

func (h *Handler) CreateWorkshop(ctx context.Context, req *connect.Request[workshopv1.CreateWorkshopRequest]) (*connect.Response[workshopv1.CreateWorkshopResponse], error) {
	input := CreateInput{
		CNPJ:     req.Msg.Cnpj,
		Name:     req.Msg.Name,
		Address:  req.Msg.Address,
		Password: req.Msg.Password,
	}
	if err := input.Validate(); err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err)
	}

	passwordHash, err := auth.HashPassword(input.Password)
	if err != nil {
		h.logger.ErrorContext(ctx, "hashing workshop password failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to create workshop"))
	}

	w, err := h.repo.Create(ctx, input, passwordHash)
	if errors.Is(err, ErrDuplicateCNPJ) {
		return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("this CNPJ is already registered"))
	}
	if err != nil {
		// The CNPJ is logged for support; the password never is.
		h.logger.ErrorContext(ctx, "create workshop failed", "err", fmt.Errorf("creating workshop: %w", err))
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to create workshop"))
	}

	token, err := h.issueToken(ctx, w.ID)
	if err != nil {
		return nil, err
	}

	return connect.NewResponse(&workshopv1.CreateWorkshopResponse{
		Workshop: toProto(w),
		Token:    token,
	}), nil
}

func (h *Handler) Login(ctx context.Context, req *connect.Request[workshopv1.LoginRequest]) (*connect.Response[workshopv1.LoginResponse], error) {
	// One message for every failure below: never reveal whether the CNPJ
	// exists, only that the pair did not authenticate.
	unauthenticated := connect.NewError(connect.CodeUnauthenticated, errors.New("CNPJ ou senha inválidos"))

	cnpj := NormalizeCNPJ(req.Msg.Cnpj)
	if cnpj == "" || req.Msg.Password == "" {
		return nil, unauthenticated
	}

	w, err := h.repo.FindByCNPJ(ctx, cnpj)
	if err != nil {
		h.logger.ErrorContext(ctx, "workshop login lookup failed", "err", err)
		return nil, connect.NewError(connect.CodeInternal, errors.New("failed to sign in"))
	}

	digest := dummyHash
	if w != nil {
		digest = w.PasswordHash
	}
	if !auth.CheckPassword(digest, req.Msg.Password) || w == nil {
		return nil, unauthenticated
	}

	token, err := h.issueToken(ctx, w.ID)
	if err != nil {
		return nil, err
	}

	return connect.NewResponse(&workshopv1.LoginResponse{
		Workshop: toProto(w),
		Token:    token,
	}), nil
}

func (h *Handler) issueToken(ctx context.Context, workshopID string) (string, error) {
	token, err := h.signer.Issue(auth.Subject{Kind: auth.KindWorkshop, ID: workshopID}, time.Now())
	if err != nil {
		h.logger.ErrorContext(ctx, "issuing workshop token failed", "err", err)
		return "", connect.NewError(connect.CodeInternal, errors.New("failed to start session"))
	}
	return token, nil
}

func toProto(w *Workshop) *workshopv1.Workshop {
	return &workshopv1.Workshop{
		Id:        w.ID,
		Cnpj:      w.CNPJ,
		Name:      w.Name,
		Address:   w.Address,
		Verified:  w.Verified,
		CreatedAt: timestamppb.New(w.CreatedAt),
	}
}
