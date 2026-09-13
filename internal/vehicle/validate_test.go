package vehicle

import "testing"

func TestNormalizePlate(t *testing.T) {
	cases := map[string]string{
		"abc-1234": "ABC1234",
		"ABC1D23":  "ABC1D23",
		"abc 1d23": "ABC1D23",
	}
	for input, want := range cases {
		if got := NormalizePlate(input); got != want {
			t.Errorf("NormalizePlate(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestCreateInputValidate(t *testing.T) {
	valid := CreateInput{
		Plate:  "ABC1234",
		Chassi: "9BWZZZ377VT004251",
		Make:   "Honda",
		Model:  "CG 160",
		Year:   2022,
	}
	if err := valid.Validate(); err != nil {
		t.Fatalf("expected valid input, got error: %v", err)
	}

	invalidPlate := valid
	invalidPlate.Plate = "XYZ"
	if err := invalidPlate.Validate(); err == nil {
		t.Fatal("expected error for invalid plate, got nil")
	}

	invalidChassi := valid
	invalidChassi.Chassi = "TOO-SHORT"
	if err := invalidChassi.Validate(); err == nil {
		t.Fatal("expected error for invalid chassi, got nil")
	}

	lowerChassi := CreateInput{Plate: "abc1234", Chassi: "9bwzzz377vt004251", Make: "Honda", Model: "CG", Year: 2022}
	if err := lowerChassi.Normalized().Validate(); err != nil {
		t.Fatalf("expected normalized input to be valid, got: %v", err)
	}

	blankMake := valid
	blankMake.Make = "   "
	if err := blankMake.Normalized().Validate(); err == nil {
		t.Fatal("expected error for blank make, got nil")
	}

	invalidYear := valid
	invalidYear.Year = 1900
	if err := invalidYear.Validate(); err == nil {
		t.Fatal("expected error for invalid year, got nil")
	}
}

func BenchmarkNormalizePlate(b *testing.B) {
	for b.Loop() {
		NormalizePlate("abc-1234")
	}
}

func BenchmarkCreateInputValidate(b *testing.B) {
	input := CreateInput{
		Plate:  "ABC1234",
		Chassi: "9BWZZZ377VT004251",
		Make:   "Honda",
		Model:  "CG 160",
		Year:   2022,
	}
	for b.Loop() {
		_ = input.Validate()
	}
}
