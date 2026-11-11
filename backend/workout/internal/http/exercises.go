package http

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/marcus-coube/lyfta/workout/internal/domain"
	"github.com/marcus-coube/lyfta/workout/internal/media"
	"github.com/marcus-coube/lyfta/workout/internal/repo"
)

// ExerciseHandler expõe a biblioteca de exercícios (P1.3): a global da Lyfta
// e a do tenant no mesmo endpoint, resolvidas no locale do usuário (ADR-010,
// ADR-011 §2).
type ExerciseHandler struct {
	logger    *slog.Logger
	exercises *repo.ExerciseRepo
	presigner *media.Presigner
}

// NewExerciseHandler cria o handler da biblioteca.
func NewExerciseHandler(logger *slog.Logger, exercises *repo.ExerciseRepo, presigner *media.Presigner) *ExerciseHandler {
	return &ExerciseHandler{logger: logger, exercises: exercises, presigner: presigner}
}

// maxNameLen limita nome e instruções — o banco aceita TEXT, a API não deve.
const (
	maxNameLen         = 120
	maxInstructionsLen = 4000
)

type exerciseResponse struct {
	ID string `json:"id"`
	// Name/Instructions no locale resolvido; Locale diz qual foi encontrado,
	// para o cliente saber que caiu no fallback (ADR-011 §2).
	Name          string    `json:"name"`
	Instructions  string    `json:"instructions"`
	Locale        string    `json:"locale"`
	PrimaryMuscle string    `json:"primary_muscle"`
	Equipment     string    `json:"equipment"`
	Level         string    `json:"level"`
	MediaURL      string    `json:"media_url,omitempty"`
	MediaType     string    `json:"media_type,omitempty"`
	IsGlobal      bool      `json:"is_global"`
	Status        string    `json:"status"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type exerciseListResponse struct {
	Items      []exerciseResponse `json:"items"`
	NextCursor string             `json:"next_cursor,omitempty"`
}

type translationDTO struct {
	Locale       string `json:"locale"`
	Name         string `json:"name"`
	Instructions string `json:"instructions"`
}

type exerciseDetailResponse struct {
	exerciseResponse
	// CanonicalName é a coluna `exercises.name` (língua-fonte), o que a tela
	// de edição precisa mostrar junto das traduções.
	CanonicalName string           `json:"canonical_name"`
	Translations  []translationDTO `json:"translations"`
}

type exerciseRequest struct {
	Name          string           `json:"name"`
	PrimaryMuscle string           `json:"primary_muscle"`
	Equipment     string           `json:"equipment"`
	Level         string           `json:"level"`
	MediaURL      string           `json:"media_url"`
	MediaType     string           `json:"media_type"`
	Status        string           `json:"status"`
	Instructions  string           `json:"instructions"`
	Translations  []translationDTO `json:"translations"`
}

// List responde a página da biblioteca visível para o tenant.
//
// Sem restrição de papel: o aluno também lê a biblioteca (nome e mídia do
// exercício aparecem no treino dele). Escrever é que é do professor.
func (h *ExerciseHandler) List(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}

	locale, apiErr := requestLocale(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	q := r.URL.Query()
	filter := domain.ExerciseFilter{
		Query:         strings.TrimSpace(q.Get("q")),
		PrimaryMuscle: strings.TrimSpace(q.Get("muscle")),
		Equipment:     strings.TrimSpace(q.Get("equipment")),
		Level:         domain.Level(strings.TrimSpace(q.Get("level"))),
		Locale:        locale,
	}
	// Filtro fora da taxonomia é erro do cliente, não lista vazia silenciosa.
	if filter.PrimaryMuscle != "" && !domain.IsValidMuscle(filter.PrimaryMuscle) {
		writeError(w, errValidation("muscle"))
		return
	}
	if filter.Equipment != "" && !domain.IsValidEquipment(filter.Equipment) {
		writeError(w, errValidation("equipment"))
		return
	}
	if filter.Level != "" && !domain.IsValidLevel(filter.Level) {
		writeError(w, errValidation("level"))
		return
	}
	if raw := q.Get("limit"); raw != "" {
		limit, err := strconv.Atoi(raw)
		if err != nil || limit <= 0 {
			writeError(w, errValidation("limit"))
			return
		}
		filter.Limit = limit
	}
	if raw := q.Get("cursor"); raw != "" {
		name, id, err := decodeCursor(raw)
		if err != nil {
			writeError(w, errInvalidCursor())
			return
		}
		filter.CursorName, filter.CursorID = name, id
	}

	items, hasMore, err := h.exercises.List(r.Context(), tenantID, filter)
	if err != nil {
		h.logger.Error("exercises_list_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	resp := exerciseListResponse{Items: make([]exerciseResponse, 0, len(items))}
	for _, item := range items {
		resp.Items = append(resp.Items, h.toResponse(r.Context(), item.Exercise,
			item.DisplayName, item.Instructions, item.NameLocale))
	}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		resp.NextCursor = encodeCursor(last.SortKey, last.ID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// Get responde um exercício com todas as suas traduções.
func (h *ExerciseHandler) Get(w http.ResponseWriter, r *http.Request) {
	tenantID, ok := TenantFromContext(r.Context())
	if !ok {
		writeError(w, errUnauthenticated())
		return
	}
	locale, apiErr := requestLocale(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	exercise, translations, apiErr := h.load(r.Context(), tenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}

	name, instructions, found := resolveTranslation(translations, locale, exercise.Name)
	detail := exerciseDetailResponse{
		exerciseResponse: h.toResponse(r.Context(), exercise, name, instructions, found),
		CanonicalName:    exercise.Name,
		Translations:     make([]translationDTO, 0, len(translations)),
	}
	for _, t := range translations {
		detail.Translations = append(detail.Translations, translationDTO{
			Locale: string(t.Locale), Name: t.Name, Instructions: t.Instructions,
		})
	}
	writeJSON(w, http.StatusOK, detail)
}

// Create cadastra um exercício do tenant (ADR-010 §3). Global não se cria por
// aqui: a policy de escrita nem enxerga tenant_id NULL.
func (h *ExerciseHandler) Create(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	req, apiErr := decodeExerciseRequest(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	exercise, translations, apiErr := h.validate(req, claims.TenantID, claims.Locale, false)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	exercise.CreatedBy = claims.Subject

	created, err := h.exercises.Create(r.Context(), exercise, translations)
	if err != nil {
		h.logger.Error("exercise_create_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	locale, _ := requestLocale(r)
	name, instructions, found := resolveTranslation(translations, locale, created.Name)
	writeJSON(w, http.StatusCreated, h.toResponse(r.Context(), created, name, instructions, found))
}

// Update sobrescreve um exercício do próprio tenant.
func (h *ExerciseHandler) Update(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok || claims.TenantID == "" {
		writeError(w, errUnauthenticated())
		return
	}

	current, _, apiErr := h.load(r.Context(), claims.TenantID, chi.URLParam(r, "id"))
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	// A biblioteca global é somente leitura para o tenant (ADR-010 §3). Sem
	// esta checagem o RLS recusaria do mesmo jeito, mas devolvendo 404 — e
	// "não existe" é resposta errada para um exercício que o coach está vendo
	// na tela. O caminho para ajustar um global é clonar.
	if current.IsGlobal() {
		writeError(w, errExerciseIsGlobal())
		return
	}

	req, apiErr := decodeExerciseRequest(r)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	exercise, translations, apiErr := h.validate(req, claims.TenantID, claims.Locale, true)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	exercise.ID = current.ID

	updated, err := h.exercises.Update(r.Context(), exercise, translations)
	if errors.Is(err, repo.ErrNotFound) {
		writeError(w, errNotFound("exercise"))
		return
	}
	if err != nil {
		h.logger.Error("exercise_update_failed", slog.Any("error", err))
		writeError(w, errInternal())
		return
	}

	locale, _ := requestLocale(r)
	name, instructions, found := resolveTranslation(translations, locale, updated.Name)
	writeJSON(w, http.StatusOK, h.toResponse(r.Context(), updated, name, instructions, found))
}

// load lê o exercício e suas traduções, traduzindo o erro do repositório.
func (h *ExerciseHandler) load(ctx context.Context, tenantID, id string) (domain.Exercise, []domain.ExerciseTranslation, *APIError) {
	if id == "" {
		apiErr := errValidation("id")
		return domain.Exercise{}, nil, &apiErr
	}
	exercise, err := h.exercises.GetByID(ctx, tenantID, id)
	if errors.Is(err, repo.ErrNotFound) {
		apiErr := errNotFound("exercise")
		return domain.Exercise{}, nil, &apiErr
	}
	if err != nil {
		h.logger.Error("exercise_get_failed", slog.Any("error", err))
		apiErr := errInternal()
		return domain.Exercise{}, nil, &apiErr
	}
	translations, err := h.exercises.Translations(ctx, tenantID, exercise.ID)
	if err != nil {
		h.logger.Error("exercise_translations_failed", slog.Any("error", err))
		apiErr := errInternal()
		return domain.Exercise{}, nil, &apiErr
	}
	return exercise, translations, nil
}

// validate converte o corpo da requisição em domínio, recusando o que fugir da
// taxonomia (ADR-010 §4) ou apontar mídia fora da pasta do tenant.
func (h *ExerciseHandler) validate(req exerciseRequest, tenantID, claimLocale string, allowStatus bool) (domain.Exercise, []domain.ExerciseTranslation, *APIError) {
	fail := func(field string) (domain.Exercise, []domain.ExerciseTranslation, *APIError) {
		apiErr := errValidation(field)
		return domain.Exercise{}, nil, &apiErr
	}

	name := strings.TrimSpace(req.Name)
	if name == "" || len(name) > maxNameLen {
		return fail("name")
	}
	if !domain.IsValidMuscle(req.PrimaryMuscle) {
		return fail("primary_muscle")
	}
	if !domain.IsValidEquipment(req.Equipment) {
		return fail("equipment")
	}
	level := domain.Level(req.Level)
	if level == "" {
		level = domain.LevelBeginner
	}
	if !domain.IsValidLevel(level) {
		return fail("level")
	}

	status := domain.ExerciseStatus(req.Status)
	switch {
	case status == "":
		status = domain.ExerciseStatusActive
	case !allowStatus:
		return fail("status")
	case status != domain.ExerciseStatusActive && status != domain.ExerciseStatusArchived:
		return fail("status")
	}

	mediaURL := strings.TrimSpace(req.MediaURL)
	mediaType := domain.MediaType(strings.TrimSpace(req.MediaType))
	if (mediaURL == "") != (mediaType == "") {
		// O CHECK da tabela exige os dois ou nenhum; recusar aqui dá erro
		// traduzível em vez de 500 do banco.
		return fail("media_url")
	}
	if mediaURL != "" {
		if mediaType != domain.MediaTypeGIF && mediaType != domain.MediaTypeVideo {
			return fail("media_type")
		}
		// A mídia tem de ser um objeto que este tenant subiu pelo presign
		// (P1.2) — nunca uma URL arbitrária nem a pasta de outro tenant.
		if _, ok := h.presigner.KeyForTenant(mediaURL, tenantID); !ok {
			return fail("media_url")
		}
	}

	translations, apiErr := buildTranslations(req, tenantID, claimLocale)
	if apiErr != nil {
		return domain.Exercise{}, nil, apiErr
	}

	return domain.Exercise{
		TenantID:      tenantID,
		Name:          name,
		PrimaryMuscle: req.PrimaryMuscle,
		Equipment:     req.Equipment,
		Level:         level,
		MediaURL:      mediaURL,
		MediaType:     mediaType,
		Status:        status,
	}, translations, nil
}

// buildTranslations monta as traduções a gravar. `instructions` no corpo é o
// atalho do caso comum — o coach descreve o exercício no idioma dele e não
// preenche três formulários; vira uma tradução no locale da claim. Exercício
// sem tradução nenhuma continua legível: a leitura cai na coluna canônica.
func buildTranslations(req exerciseRequest, tenantID, claimLocale string) ([]domain.ExerciseTranslation, *APIError) {
	fail := func(field string) *APIError {
		apiErr := errValidation(field)
		return &apiErr
	}

	out := make([]domain.ExerciseTranslation, 0, len(req.Translations)+1)
	seen := map[domain.Locale]bool{}
	for _, t := range req.Translations {
		locale, ok := domain.ParseLocale(t.Locale)
		if !ok || seen[locale] {
			return nil, fail("translations.locale")
		}
		name := strings.TrimSpace(t.Name)
		if name == "" || len(name) > maxNameLen {
			return nil, fail("translations.name")
		}
		if len(t.Instructions) > maxInstructionsLen {
			return nil, fail("translations.instructions")
		}
		seen[locale] = true
		out = append(out, domain.ExerciseTranslation{
			TenantID: tenantID, Locale: locale, Name: name,
			Instructions: strings.TrimSpace(t.Instructions),
		})
	}

	instructions := strings.TrimSpace(req.Instructions)
	if instructions == "" {
		return out, nil
	}
	if len(instructions) > maxInstructionsLen {
		return nil, fail("instructions")
	}
	locale, ok := domain.ParseLocale(claimLocale)
	if !ok {
		locale = domain.LocaleSource
	}
	if seen[locale] {
		// Mandou os dois para o mesmo idioma: o bloco explícito vence.
		return out, nil
	}
	return append(out, domain.ExerciseTranslation{
		TenantID: tenantID, Locale: locale,
		Name: strings.TrimSpace(req.Name), Instructions: instructions,
	}), nil
}

// toResponse serializa o exercício já com a mídia resolvida para uma URL
// válida agora (bucket privado assina de novo a cada leitura — ver
// media.ResolveURL).
func (h *ExerciseHandler) toResponse(ctx context.Context, e domain.Exercise, name, instructions string, locale domain.Locale) exerciseResponse {
	return exerciseToResponse(ctx, h.presigner, e, name, instructions, locale)
}

// exerciseToResponse é a mesma serialização sem depender do handler: o pull
// incremental (P1.5) devolve exercícios pelo mesmo formato da biblioteca, e o
// app não deve precisar de dois parsers para o mesmo objeto.
func exerciseToResponse(ctx context.Context, presigner *media.Presigner, e domain.Exercise, name, instructions string, locale domain.Locale) exerciseResponse {
	if name == "" {
		name = e.Name
	}
	if locale == "" {
		locale = domain.LocaleSource
	}
	return exerciseResponse{
		ID:            e.ID,
		Name:          name,
		Instructions:  instructions,
		Locale:        string(locale),
		PrimaryMuscle: e.PrimaryMuscle,
		Equipment:     e.Equipment,
		Level:         string(e.Level),
		MediaURL:      presigner.ResolveURL(ctx, e.MediaURL),
		MediaType:     string(e.MediaType),
		IsGlobal:      e.IsGlobal(),
		Status:        string(e.Status),
		UpdatedAt:     e.UpdatedAt,
	}
}

// resolveTranslation aplica a cascata de fallback do ADR-011 §2 sobre as
// traduções já carregadas (o mesmo que a LATERAL da listagem faz no banco).
func resolveTranslation(translations []domain.ExerciseTranslation, locale domain.Locale, canonicalName string) (name, instructions string, found domain.Locale) {
	for _, candidate := range domain.LocaleChain(locale) {
		for _, t := range translations {
			if t.Locale == candidate {
				return t.Name, t.Instructions, candidate
			}
		}
	}
	return canonicalName, "", domain.LocaleSource
}

// requestLocale decide em que idioma o conteúdo volta, nesta ordem: `?locale=`
// explícito, `Accept-Language` (o app manda o idioma da tela, P8.3) e, na falta
// dos dois, o locale da claim (o do tenant).
func requestLocale(r *http.Request) (domain.Locale, *APIError) {
	if raw := r.URL.Query().Get("locale"); raw != "" {
		locale, ok := domain.ParseLocale(raw)
		if !ok {
			apiErr := errValidation("locale")
			return "", &apiErr
		}
		return locale, nil
	}
	if locale, ok := acceptLanguageLocale(r.Header.Get("Accept-Language")); ok {
		return locale, nil
	}
	if claims, ok := ClaimsFromContext(r.Context()); ok {
		if locale, ok := domain.ParseLocale(claims.Locale); ok {
			return locale, nil
		}
	}
	return domain.LocaleSource, nil
}

// acceptLanguageLocale escolhe o primeiro idioma suportado do cabeçalho, do de
// maior q para o menor (empate: ordem de aparição). Idioma desconhecido é
// ignorado, não erro: cabeçalho vem de cliente que não controlamos.
func acceptLanguageLocale(header string) (domain.Locale, bool) {
	var best domain.Locale
	bestQ := -1.0
	for _, part := range strings.Split(header, ",") {
		tag, params, _ := strings.Cut(strings.TrimSpace(part), ";")
		q := 1.0
		if v, ok := strings.CutPrefix(strings.TrimSpace(params), "q="); ok {
			parsed, err := strconv.ParseFloat(v, 64)
			if err != nil {
				continue
			}
			q = parsed
		}
		locale, ok := domain.ParseLocale(tag)
		if !ok || q <= 0 || q <= bestQ {
			continue
		}
		best, bestQ = locale, q
	}
	return best, bestQ > 0
}

func decodeExerciseRequest(r *http.Request) (exerciseRequest, *APIError) {
	var req exerciseRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr := errInvalidBody()
		return exerciseRequest{}, &apiErr
	}
	return req, nil
}

// encodeCursor/decodeCursor empacotam a chave keyset (nome normalizado + id).
// Opaco de propósito: o cliente devolve o que recebeu, e a composição da
// chave pode mudar sem quebrar contrato.
const cursorSeparator = "\x1f"

func encodeCursor(sortKey, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(sortKey + cursorSeparator + id))
}

func decodeCursor(raw string) (sortKey, id string, err error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return "", "", err
	}
	parts := strings.SplitN(string(decoded), cursorSeparator, 2)
	if len(parts) != 2 || parts[1] == "" {
		return "", "", errors.New("http: cursor malformado")
	}
	return parts[0], parts[1], nil
}
