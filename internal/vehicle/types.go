package vehicle

import "time"

type Vehicle struct {
	ID        string    `json:"id"`
	Plate     string    `json:"plate"`
	Chassi    string    `json:"chassi"`
	Make      string    `json:"make"`
	Model     string    `json:"model"`
	Year      int       `json:"year"`
	CreatedAt time.Time `json:"createdAt"`
}

type CreateInput struct {
	Plate  string `json:"plate"`
	Chassi string `json:"chassi"`
	Make   string `json:"make"`
	Model  string `json:"model"`
	Year   int    `json:"year"`
}
