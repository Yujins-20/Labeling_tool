defmodule Hyacinth.Labeling.LabelJob do
  use Hyacinth.Schema
  import Ecto.Changeset
  import Hyacinth.Validators

  alias Hyacinth.Accounts.User
  alias Hyacinth.Warehouse.Dataset
  alias Hyacinth.Labeling.{LabelSession, LabelJobType}

  schema "label_jobs" do
    field :name, :string
    field :description, :string

    field :prompt, :string
    field :label_options, {:array, :string}

    field :sample_size, :integer, default: nil  # default를 nil로 설정
    field :type, Ecto.Enum, values: [:classification, :comparison_exhaustive, :comparison_mergesort, :comparison_timsort,
                                   :comparison_quicksort, :comparison_heapsort], default: :classification  # 새로운 타입 추가
    field :options, :map, default: %{}
    field :label_options_string, :string, virtual: true

    belongs_to :dataset, Dataset
    belongs_to :created_by_user, User

    has_one :blueprint, LabelSession, foreign_key: :job_id, where: [blueprint: true]

    timestamps()
  end

  @doc false
  def changeset(label_job, attrs) do
    label_job
    |> cast(attrs, [:name, :description, :prompt, :label_options_string,
                   :type, :options, :dataset_id, :sample_size])
    |> validate_required([:name, :type, :options, :dataset_id])
    |> validate_length(:name, min: 1, max: 300)
    |> validate_length(:description, min: 1, max: 2000)
    |> validate_sample_size()
    |> validate_job_type_options()
    |> validate_label_options()  # 하나의 함수만 사용
  end

  defp validate_label_options(changeset) do
    case get_field(changeset, :type) do
      :classification ->
        changeset
        |> validate_required([:label_options_string])
        |> validate_length(:label_options_string, min: 1, max: 1000)
        |> parse_comma_separated_string(:label_options_string, :label_options)
      type when type in [:comparison_exhaustive, :comparison_mergesort,
                        :comparison_quicksort, :comparison_heapsort,
                        :comparison_timsort] ->
        # comparison 타입들에 대해 명시적으로 label_options를 설정
        put_change(changeset, :label_options, ["First Image", "Second Image"])
      _ ->
        add_error(changeset, :type, "invalid job type")
    end
  end

  defp validate_sample_size(changeset) do
    case get_field(changeset, :sample_size) do
      nil -> changeset
      size when is_integer(size) and size > 2 -> changeset
      _ -> add_error(changeset, :sample_size, "must be a positive integer")
    end
  end

  defp validate_job_type_options(%Ecto.Changeset{} = changeset) do
    job_type = get_field(changeset, :type)
    options_params = get_field(changeset, :options)

    options_changeset = LabelJobType.options_changeset(job_type, options_params)
    if options_changeset.valid? do
      validated_options =
        options_changeset
        |> Ecto.Changeset.apply_action!(:insert)
        |> Map.from_struct()
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

      put_change(changeset, :options, validated_options)
    else
      message = "not valid for type %{job_type}"
      keys = [job_type: job_type]
      add_error(changeset, :options, message, keys)
    end
  end
end
