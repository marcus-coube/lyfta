// Package repo contém o acesso a dados (pgx) do serviço identity, um arquivo
// por agregado, além da criação do pool de conexões e do helper de RLS.
package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool cria o pool de conexões pgx a partir da DATABASE_URL.
func NewPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("repo: criar pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("repo: ping no banco: %w", err)
	}
	return pool, nil
}
