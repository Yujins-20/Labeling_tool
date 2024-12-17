# lib/hyacinth/labeling/label_job_type/comparison_heapsort.ex
defmodule Hyacinth.Labeling.LabelJobType.ComparisonHeapsort do  # 모듈 이름 수정
  alias Hyacinth.Labeling.LabelJobType

  alias Hyacinth.Warehouse.Object
  alias Hyacinth.Labeling.{LabelJob, LabelSession, LabelElement}

  defmodule ComparisonHeapsortOptions do  # Options 모듈 이름도 수정
    use Ecto.Schema
    import Ecto.Changeset
    import Hyacinth.Validators

    @primary_key false
    embedded_schema do
      field :randomize, :boolean, default: true
      field :random_seed, :integer, default: 123
      field :comparison_label_options_raw_input, :string, default: "First Image, Second Image"
      field :comparison_label_options, {:array, :string}
    end

    def changeset(schema, params) do
      schema
      |> cast(params, [:randomize, :random_seed, :comparison_label_options_raw_input])
      |> validate_required([:randomize, :random_seed, :comparison_label_options_raw_input])
      |> validate_number(:random_seed, greater_than: 0)
      |> parse_comma_separated_string(:comparison_label_options_raw_input, :comparison_label_options, keep_string: true)
    end

    def parse(params) do
      %ComparisonHeapsortOptions{}
      |> changeset(params)
      |> apply_changes()
    end
  end

  @behaviour LabelJobType

  @impl LabelJobType
  def name, do: "Comparison (Heap Sort)"

  @impl LabelJobType
  def options_changeset(params), do: ComparisonHeapsortOptions.changeset(%ComparisonHeapsortOptions{}, params)

  @impl LabelJobType
  def render_form(assigns) do
    import Phoenix.LiveView.Helpers
    import Phoenix.HTML.Form
    import HyacinthWeb.ErrorHelpers

    ~H"""
    <div class="form-content">
      <p>
        <%= label @form, :randomize %>
        <%= checkbox @form, :randomize %>
        <%= error_tag @form, :randomize %>
      </p>

      <p>
        <%= label @form, :random_seed %>
        <%= number_input @form, :random_seed %>
        <%= error_tag @form, :random_seed %>
      </p>

      <p>
        <%= label @form, :comparison_label_options_raw_input, "Comparison label options" %>
        <%= text_input @form, :comparison_label_options_raw_input, placeholder: "First, Second" %>
        <%= error_tag @form, :comparison_label_options_raw_input, name: "Comparison label options" %>
      </p>
    </div>
    """
  end

  @impl LabelJobType
  def group_objects(options, objects) do
    options = ComparisonHeapsortOptions.parse(options)
    grouped = Enum.map(objects, fn %Object{} = o -> [o] end)
    if options.randomize do
      Hyacinth.RandomUtils.shuffle_seeded(options.random_seed, grouped)
    else
      grouped
    end
  end

  @impl LabelJobType
  def list_object_label_options(options) do
    options = ComparisonHeapsortOptions.parse(options)
    options.comparison_label_options
  end

  @impl LabelJobType
  def active?, do: true

  @impl LabelJobType
  def session_results(options, %LabelJob{} = job, %LabelSession{} = label_session) do
    options = ComparisonHeapsortOptions.parse(options)
    all_labeled = Enum.all?(label_session.elements, fn %LabelElement{} = element -> length(element.labels) > 0 end)

    if all_labeled do
      objects = Enum.map(job.blueprint.elements, fn %LabelElement{objects: objects} -> hd(objects) end)
      lookup_table = build_lookup_table(options, label_session.elements)

      case find_next_group(objects, lookup_table) do
        {:labeling_complete, objects_sorted} ->
          objects_sorted
          |> Enum.with_index()
          |> Enum.map(fn {obj, i} -> {obj, "No. #{i + 1}"} end)
          |> Enum.reverse()

        _next_group -> []
      end
    else
      []
    end
  end

  @impl LabelJobType
  def job_results(_options, _job, _label_sessions), do: []

  @impl LabelJobType
  def next_group(options, blueprint_elements, session_elements) do
    options = ComparisonHeapsortOptions.parse(options)
    objects = Enum.map(blueprint_elements, fn %LabelElement{objects: objects} -> hd(objects) end)
    lookup_table = build_lookup_table(options, session_elements)

    case find_next_group(objects, lookup_table) do
      {:labeling_complete, _objects_sorted} -> :labeling_complete
      next_group -> next_group
    end
  end

  defp build_lookup_table(%ComparisonHeapsortOptions{} = options, session_elements) do
    Enum.reduce(session_elements, %{}, fn %LabelElement{} = element, acc ->
      [%Object{} = obj1, %Object{} = obj2] = element.objects
      greater_or_equal? = hd(element.labels).value.option != Enum.at(options.comparison_label_options, 1)

      Map.update(acc, obj1.id, %{obj2.id => greater_or_equal?}, fn existing ->
        Map.put(existing, obj2.id, greater_or_equal?)
      end)
    end)
  end

  defmodule UnknownLookupException do
    defexception [:message, :obj1, :obj2]
  end

  defp find_next_group(objects, lookup_table) do
    try do
      objects_sorted =
        Enum.sort(objects, fn %Object{} = obj1, %Object{} = obj2 ->
          if Map.has_key?(lookup_table, obj1.id) and Map.has_key?(lookup_table[obj1.id], obj2.id) do
            lookup_table[obj1.id][obj2.id]
          else
            raise UnknownLookupException, message: "Unknown lookup #{obj1.id} #{obj2.id}", obj1: obj1, obj2: obj2
          end
        end)

      {:labeling_complete, objects_sorted}
    rescue
      e in UnknownLookupException ->
        [e.obj1, e.obj2]
    end
  end
end
