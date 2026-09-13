package servicerecord

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// selectRecords is the shared projection: a record always travels with enough
// of its vehicle and workshop to render a history row without a second query.
const selectRecords = `
	SELECT sr.id, sr.workshop_id, v.plate, v.make, v.model, v.year, w.name, m.name,
	       sr.mileage_km, sr.cost_cents, sr.notes, sr.created_at,
	       (SELECT p.id FROM service_records p WHERE p.superseded_by = sr.id),
	       sr.superseded_by
	FROM service_records sr
	JOIN vehicles v ON v.id = sr.vehicle_id
	JOIN workshops w ON w.id = sr.workshop_id
	LEFT JOIN mechanics m ON m.id = sr.mechanic_id`

func scanRecords(rows pgx.Rows) ([]ServiceRecord, error) {
	defer rows.Close()

	var records []ServiceRecord
	for rows.Next() {
		var r ServiceRecord
		if err := rows.Scan(
			&r.ID, &r.WorkshopID, &r.Vehicle.Plate, &r.Vehicle.Make, &r.Vehicle.Model, &r.Vehicle.Year,
			&r.WorkshopName, &r.MechanicName,
			&r.MileageKm, &r.CostCents, &r.Notes, &r.CreatedAt, &r.RevisesRecordID,
			&r.SupersededByID,
		); err != nil {
			return nil, err
		}
		records = append(records, r)
	}
	return records, rows.Err()
}

// hydrate loads operations, parts and attachments for every record in one
// query each, instead of three queries per record.
func (r *Repository) hydrate(ctx context.Context, records []ServiceRecord) error {
	if len(records) == 0 {
		return nil
	}

	ids := make([]string, len(records))
	index := make(map[string]*ServiceRecord, len(records))
	for i := range records {
		ids[i] = records[i].ID
		index[records[i].ID] = &records[i]
	}

	opRows, err := r.pool.Query(ctx,
		`SELECT service_record_id, type FROM service_record_operations
		 WHERE service_record_id = ANY($1) ORDER BY type`, ids)
	if err != nil {
		return fmt.Errorf("loading operations: %w", err)
	}
	if err := eachRow(opRows, func(rows pgx.Rows) error {
		var recordID string
		var op Operation
		if err := rows.Scan(&recordID, &op); err != nil {
			return err
		}
		index[recordID].Operations = append(index[recordID].Operations, op)
		return nil
	}); err != nil {
		return fmt.Errorf("loading operations: %w", err)
	}

	partRows, err := r.pool.Query(ctx,
		`SELECT service_record_id, name, quantity, cost_cents FROM parts
		 WHERE service_record_id = ANY($1) ORDER BY name`, ids)
	if err != nil {
		return fmt.Errorf("loading parts: %w", err)
	}
	if err := eachRow(partRows, func(rows pgx.Rows) error {
		var recordID string
		var p Part
		if err := rows.Scan(&recordID, &p.Name, &p.Quantity, &p.CostCents); err != nil {
			return err
		}
		index[recordID].Parts = append(index[recordID].Parts, p)
		return nil
	}); err != nil {
		return fmt.Errorf("loading parts: %w", err)
	}

	attachmentRows, err := r.pool.Query(ctx,
		`SELECT service_record_id, id, url, kind, phase FROM attachments
		 WHERE service_record_id = ANY($1) ORDER BY created_at`, ids)
	if err != nil {
		return fmt.Errorf("loading attachments: %w", err)
	}
	if err := eachRow(attachmentRows, func(rows pgx.Rows) error {
		var recordID string
		var a Attachment
		if err := rows.Scan(&recordID, &a.ID, &a.URL, &a.Kind, &a.Phase); err != nil {
			return err
		}
		index[recordID].Attachments = append(index[recordID].Attachments, a)
		return nil
	}); err != nil {
		return fmt.Errorf("loading attachments: %w", err)
	}

	return nil
}

func eachRow(rows pgx.Rows, scan func(pgx.Rows) error) error {
	defer rows.Close()
	for rows.Next() {
		if err := scan(rows); err != nil {
			return err
		}
	}
	return rows.Err()
}

// validID keeps a malformed id away from the uuid column, where Postgres would
// fail the query instead of simply finding nothing.
func validID(id string) bool {
	return len(id) == 36 && uuid.Validate(id) == nil
}

func (r *Repository) FindByID(ctx context.Context, id string) (*ServiceRecord, error) {
	if !validID(id) {
		return nil, nil
	}
	rows, err := r.pool.Query(ctx, selectRecords+` WHERE sr.id = $1`, id)
	if err != nil {
		return nil, err
	}
	records, err := scanRecords(rows)
	if err != nil {
		return nil, err
	}
	if len(records) == 0 {
		return nil, nil
	}
	if err := r.hydrate(ctx, records); err != nil {
		return nil, err
	}
	return &records[0], nil
}

func (r *Repository) ListByPlate(ctx context.Context, plate string, limit int) (*VehicleSummary, []ServiceRecord, error) {
	var vehicleID string
	var summary VehicleSummary
	err := r.pool.QueryRow(ctx,
		`SELECT id, plate, make, model, year FROM vehicles WHERE plate = $1`, plate,
	).Scan(&vehicleID, &summary.Plate, &summary.Make, &summary.Model, &summary.Year)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}

	rows, err := r.pool.Query(ctx,
		selectRecords+` WHERE sr.vehicle_id = $1 AND sr.superseded_by IS NULL
		 ORDER BY sr.created_at DESC LIMIT $2`, vehicleID, limit)
	if err != nil {
		return nil, nil, err
	}
	records, err := scanRecords(rows)
	if err != nil {
		return nil, nil, err
	}
	if err := r.hydrate(ctx, records); err != nil {
		return nil, nil, err
	}
	return &summary, records, nil
}

func (r *Repository) ListByWorkshop(ctx context.Context, workshopID string, limit int) ([]ServiceRecord, error) {
	rows, err := r.pool.Query(ctx,
		selectRecords+` WHERE sr.workshop_id = $1 AND sr.superseded_by IS NULL
		 ORDER BY sr.created_at DESC LIMIT $2`, workshopID, limit)
	if err != nil {
		return nil, err
	}
	records, err := scanRecords(rows)
	if err != nil {
		return nil, err
	}
	if err := r.hydrate(ctx, records); err != nil {
		return nil, err
	}
	return records, nil
}

func (r *Repository) CountByWorkshopSince(ctx context.Context, workshopID string, since time.Time) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT count(*) FROM service_records
		 WHERE workshop_id = $1 AND created_at >= $2 AND superseded_by IS NULL`,
		workshopID, since).Scan(&count)
	return count, err
}

// Create writes the record, its operations and its parts as one transaction:
// a record that lost its operations halfway through would be history nobody
// could interpret.
func (r *Repository) Create(ctx context.Context, input CreateInput) (*ServiceRecord, error) {
	return r.write(ctx, input, nil)
}

// Revise adds the correction and points the original at it, in one
// transaction: a superseded record with no replacement would erase history.
func (r *Repository) Revise(ctx context.Context, workshopID, recordID string, input CreateInput) (*ServiceRecord, error) {
	return r.write(ctx, input, &revision{workshopID: workshopID, recordID: recordID})
}

type revision struct {
	workshopID string
	recordID   string
}

func (r *Repository) write(ctx context.Context, input CreateInput, rev *revision) (*ServiceRecord, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if rev != nil {
		if err := checkRevisable(ctx, tx, rev); err != nil {
			return nil, err
		}
	}

	var vehicleID string
	err = tx.QueryRow(ctx, `SELECT id FROM vehicles WHERE plate = $1`, input.Plate).Scan(&vehicleID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrVehicleNotFound
	}
	if err != nil {
		return nil, err
	}

	// A correction may lower the mileage: fixing a typo is the point of it.
	if rev == nil && !input.ConfirmLowerMileage {
		if err := checkMileage(ctx, tx, vehicleID, input.MileageKm); err != nil {
			return nil, err
		}
	}

	mechanicID, err := upsertMechanic(ctx, tx, input.WorkshopID, input.MechanicName)
	if err != nil {
		return nil, fmt.Errorf("resolving mechanic: %w", err)
	}

	var recordID string
	if err := tx.QueryRow(ctx,
		`INSERT INTO service_records (vehicle_id, workshop_id, mechanic_id, mileage_km, cost_cents, notes)
		 VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
		vehicleID, input.WorkshopID, mechanicID, input.MileageKm, input.CostCents, input.Notes,
	).Scan(&recordID); err != nil {
		return nil, err
	}

	for _, op := range input.Operations {
		if _, err := tx.Exec(ctx,
			`INSERT INTO service_record_operations (service_record_id, type) VALUES ($1, $2)`,
			recordID, string(op)); err != nil {
			return nil, fmt.Errorf("inserting operation %q: %w", op, err)
		}
	}

	for _, part := range input.Parts {
		if _, err := tx.Exec(ctx,
			`INSERT INTO parts (service_record_id, name, quantity, cost_cents) VALUES ($1, $2, $3, $4)`,
			recordID, strings.TrimSpace(part.Name), part.Quantity, part.CostCents); err != nil {
			return nil, fmt.Errorf("inserting part: %w", err)
		}
	}

	if rev != nil {
		if _, err := tx.Exec(ctx,
			`UPDATE service_records SET superseded_by = $1 WHERE id = $2`,
			recordID, rev.recordID); err != nil {
			return nil, fmt.Errorf("superseding %s: %w", rev.recordID, err)
		}
		// Photos and the invoice describe the job, not the typo being fixed,
		// so they move to the correction rather than vanish with the original.
		if _, err := tx.Exec(ctx,
			`INSERT INTO attachments (service_record_id, url, kind, phase, created_at)
			 SELECT $1, url, kind, phase, created_at FROM attachments WHERE service_record_id = $2`,
			recordID, rev.recordID); err != nil {
			return nil, fmt.Errorf("carrying attachments of %s: %w", rev.recordID, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return r.FindByID(ctx, recordID)
}

// AddAttachment refuses a record the workshop does not own, so one shop cannot
// staple photos onto another's work.
func (r *Repository) AddAttachment(ctx context.Context, workshopID, recordID string, a Attachment) (*Attachment, error) {
	if !validID(recordID) {
		return nil, ErrRecordNotFound
	}
	var ownerWorkshop string
	err := r.pool.QueryRow(ctx,
		`SELECT workshop_id FROM service_records WHERE id = $1`, recordID).Scan(&ownerWorkshop)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrRecordNotFound
	}
	if err != nil {
		return nil, err
	}
	if ownerWorkshop != workshopID {
		return nil, ErrRecordNotFound
	}

	var stored Attachment
	if err := r.pool.QueryRow(ctx,
		`INSERT INTO attachments (service_record_id, url, kind, phase)
		 VALUES ($1, $2, $3, $4) RETURNING id, url, kind, phase`,
		recordID, a.URL, a.Kind, a.Phase,
	).Scan(&stored.ID, &stored.URL, &stored.Kind, &stored.Phase); err != nil {
		return nil, err
	}
	return &stored, nil
}

// checkRevisable locks the original so two concurrent corrections cannot both
// claim it, and refuses one that isn't the caller's or is already superseded.
func checkRevisable(ctx context.Context, tx pgx.Tx, rev *revision) error {
	if !validID(rev.recordID) {
		return ErrRecordNotFound
	}
	var ownerWorkshop string
	var supersededBy *string
	err := tx.QueryRow(ctx,
		`SELECT workshop_id, superseded_by FROM service_records WHERE id = $1 FOR UPDATE`,
		rev.recordID).Scan(&ownerWorkshop, &supersededBy)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrRecordNotFound
	}
	if err != nil {
		return err
	}
	if ownerWorkshop != rev.workshopID {
		return ErrRecordNotFound
	}
	if supersededBy != nil {
		return ErrAlreadySuperseded
	}
	return nil
}

func checkMileage(ctx context.Context, tx pgx.Tx, vehicleID string, mileageKm int) error {
	var highest *int
	if err := tx.QueryRow(ctx,
		`SELECT MAX(mileage_km) FROM service_records
		 WHERE vehicle_id = $1 AND superseded_by IS NULL`, vehicleID).Scan(&highest); err != nil {
		return fmt.Errorf("reading highest mileage: %w", err)
	}
	if highest != nil && mileageKm < *highest {
		return &LowerMileageError{HighestKm: *highest}
	}
	return nil
}

// upsertMechanic maps the free-text mechanic name the app collects onto the
// mechanics table, reusing the row when that shop already has someone by that
// name so the same person isn't duplicated on every service.
func upsertMechanic(ctx context.Context, tx pgx.Tx, workshopID string, name *string) (*string, error) {
	if name == nil {
		return nil, nil
	}
	trimmed := strings.TrimSpace(*name)
	if trimmed == "" {
		return nil, nil
	}

	var id string
	err := tx.QueryRow(ctx,
		`SELECT id FROM mechanics WHERE workshop_id = $1 AND lower(name) = lower($2)`,
		workshopID, trimmed).Scan(&id)
	if err == nil {
		return &id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	if err := tx.QueryRow(ctx,
		`INSERT INTO mechanics (workshop_id, name) VALUES ($1, $2) RETURNING id`,
		workshopID, trimmed).Scan(&id); err != nil {
		return nil, err
	}
	return &id, nil
}
