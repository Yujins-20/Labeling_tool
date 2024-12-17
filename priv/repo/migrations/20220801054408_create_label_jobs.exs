# priv/repo/migrations/20241208000000_create_label_jobs.exs
defmodule Hyacinth.Repo.Migrations.CreateLabelJobs do
  use Ecto.Migration

  def change do
    # 먼저 제약조건이 있는 테이블을 생성
    execute """
    CREATE TABLE label_jobs (
      id INTEGER PRIMARY KEY,
      sample_size INTEGER,
      name TEXT NOT NULL,
      description TEXT,
      prompt TEXT,
      label_options JSON NOT NULL,
      type TEXT NOT NULL CHECK (
        type IN ('classification', 'comparison_exhaustive', 'comparison_mergesort',
                'comparison_quicksort', 'comparison_heapsort', 'comparison_timsort')
      ),
      options JSON NOT NULL,
      dataset_id INTEGER NOT NULL REFERENCES datasets(id),
      created_by_user_id INTEGER NOT NULL REFERENCES users(id),
      inserted_at TEXT_DATETIME NOT NULL,
      updated_at TEXT_DATETIME NOT NULL
    )
    """

    # 인덱스 생성
    create index(:label_jobs, [:dataset_id])
    create index(:label_jobs, [:created_by_user_id])
  end

  def down do
    drop table(:label_jobs)
  end
end
