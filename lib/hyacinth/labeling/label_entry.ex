defmodule Hyacinth.Labeling.LabelEntry do
  use Hyacinth.Schema
  import Ecto.Changeset

  alias Hyacinth.Labeling.LabelJob
  alias Hyacinth.Warehouse.Element
  alias Hyacinth.Accounts.User

  schema "label_entries" do
    field :value, :string

    belongs_to :job, LabelJob
    belongs_to :element, Element
    belongs_to :created_by_user, User

    timestamps()
  end

  @doc false
  def changeset(label_entry, attrs) do
    label_entry
    |> cast(attrs, [:value, :job_id, :element_id, :created_by_user_id])
    |> validate_required([:value, :job_id, :element_id, :created_by_user_id])
  end
end