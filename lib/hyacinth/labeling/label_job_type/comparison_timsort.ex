defmodule Hyacinth.Labeling.LabelJobType.ComparisonTimsort do
  alias Hyacinth.Labeling.LabelJobType
  alias Hyacinth.Warehouse.Object
  alias Hyacinth.Labeling.{LabelJob, LabelSession, LabelElement}

  @min_run 32

  defmodule ComparisonTimsortOptions do
    use Ecto.Schema
    import Ecto.Changeset
    import Hyacinth.Validators

    @primary_key false
    embedded_schema do
      field :information_threshold, :float, default: 0.1
      field :batch_size, :integer, default: 10
      field :comparison_label_options_raw_input, :string, default: "First Image, Second Image"
      field :comparison_label_options, {:array, :string}
    end

    @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
    def changeset(schema, params) do
      schema
      |> cast(params, [:information_threshold, :batch_size, :comparison_label_options_raw_input])
      |> validate_required([:information_threshold, :batch_size, :comparison_label_options_raw_input])
      |> validate_number(:information_threshold, greater_than: 0, less_than: 1)
      |> validate_number(:batch_size, greater_than: 0)
      |> parse_comma_separated_string(:comparison_label_options_raw_input, :comparison_label_options, keep_string: true)
    end

    @spec parse(map()) :: %ComparisonTimsortOptions{}
    def parse(params) do
      %ComparisonTimsortOptions{}
      |> changeset(params)
      |> apply_changes()
    end
  end

  @behaviour LabelJobType

  @impl LabelJobType
  def name, do: "Comparison (Active TimSort)"

  @impl LabelJobType
  def options_changeset(params), do: ComparisonTimsortOptions.changeset(%ComparisonTimsortOptions{}, params)

  @impl LabelJobType
  def render_form(assigns) do
    import Phoenix.LiveView.Helpers
    import Phoenix.HTML.Form
    import HyacinthWeb.ErrorHelpers

    ~H"""
    <div class="form-content">
      <p>
        <%= label @form, :information_threshold, "Information Gain Threshold" %>
        <%= number_input @form, :information_threshold, step: "0.01", min: "0", max: "1" %>
        <%= error_tag @form, :information_threshold %>
      </p>

      <p>
        <%= label @form, :batch_size, "Batch Size for Active Sampling" %>
        <%= number_input @form, :batch_size, min: "1" %>
        <%= error_tag @form, :batch_size %>
      </p>

      <p>
        <%= label @form, :comparison_label_options_raw_input, "Comparison label options" %>
        <%= text_input @form, :comparison_label_options_raw_input, placeholder: "First, Second" %>
        <%= error_tag @form, :comparison_label_options_raw_input %>
      </p>
    </div>
    """
  end

  @impl LabelJobType
  @spec group_objects(map(), [%Object{}]) :: [[%Object{}]]
  def group_objects(options, objects) do
    options = ComparisonTimsortOptions.parse(options)

    # 전체 객체의 크기에 기반하여 초기 배치 크기를 결정
    total_size = length(objects)
    min_comparisons = div(total_size * (total_size - 1), 2)  # 최소 필요 비교 횟수
    batch_size = min(total_size, max(options.batch_size, min_comparisons))

    {initial_batch, remaining} = objects
      |> Enum.shuffle()
      |> Enum.split(batch_size)

    # min_run 크기로 나누어 초기 그룹 생성
    initial_groups = Enum.chunk_every(initial_batch, @min_run)

    # 각 그룹에서 비교 쌍 생성
    pairs = initial_groups
      |> Enum.flat_map(fn group -> generate_pairs(group, remaining) end)
      |> Enum.uniq_by(fn [obj1, obj2] ->
        if obj1.id < obj2.id, do: {obj1.id, obj2.id}, else: {obj2.id, obj1.id}
      end)

    pairs
  end

  @spec generate_pairs([%Object{}], [%Object{}]) :: [[%Object{}]]
  defp generate_pairs([], _), do: []
  defp generate_pairs([single], remaining) do
    case remaining do
      [next | _] -> [[single, next]]
      [] -> [[single, single]]
    end
  end
  defp generate_pairs(objects, _remaining) do
    objects
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [single] -> [single, single]
      pair -> pair
    end)
    |> Enum.filter(fn [a, b] -> a != b end)
  end

  @impl LabelJobType
  @spec list_object_label_options(map()) :: [String.t()]
  def list_object_label_options(options) do
    options = ComparisonTimsortOptions.parse(options)
    options.comparison_label_options
  end

  @impl LabelJobType
  def active?, do: true

  @impl LabelJobType
  @spec session_results(map(), %LabelJob{}, %LabelSession{}) :: [{%Object{}, String.t()}]
  def session_results(options, %LabelJob{} = job, %LabelSession{} = label_session) do
    options = ComparisonTimsortOptions.parse(options)

    all_labeled = Enum.all?(label_session.elements, fn %LabelElement{} = element ->
      length(element.labels) > 0
    end)

    if all_labeled do
      objects = Enum.map(job.blueprint.elements, fn %LabelElement{objects: objects} -> hd(objects) end)
      lookup_table = build_lookup_table(options, label_session.elements)

      case find_next_group(objects, lookup_table, options) do
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

  @spec build_lookup_table(%ComparisonTimsortOptions{}, [%LabelElement{}]) :: %{integer => %{integer => boolean}}
  defp build_lookup_table(%ComparisonTimsortOptions{} = options, session_elements) do
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

  @spec find_next_group([%Object{}], map(), %ComparisonTimsortOptions{}) ::
    [%Object{}] | {:labeling_complete, [%Object{}]}
  defp find_next_group(objects, lookup_table, options) do
    try do
      case select_next_comparison(objects, lookup_table, options) do
        nil ->
          objects_sorted = perform_final_sort(objects, lookup_table)
          {:labeling_complete, objects_sorted}
        {obj1, obj2} ->
          [obj1, obj2]
      end
    rescue
      e in UnknownLookupException ->
        [e.obj1, e.obj2]
    end
  end

# lib/hyacinth/labeling/label_job_type/comparison_timsort.ex

  @spec calculate_information_gain(%Object{}, %Object{}, map()) :: float()
  defp calculate_information_gain(obj1, obj2, lookup_table) do
    case {Map.get(lookup_table, obj1.id), Map.get(lookup_table, obj2.id)} do
      {nil, nil} -> 1.0
      {nil, _} -> 0.7
      {_, nil} -> 0.7
      {v1, v2} ->
        # 각 객체의 승패 기록을 기반으로 정보 이득 계산
        wins1 = Map.values(v1) |> Enum.count(&(&1))
        wins2 = Map.values(v2) |> Enum.count(&(&1))
        total1 = map_size(v1)
        total2 = map_size(v2)

        rate1 = if total1 > 0, do: wins1 / total1, else: 0.0
        rate2 = if total2 > 0, do: wins2 / total2, else: 0.0

        # 승률 차이가 클수록 더 높은 정보 이득
        abs(rate1 - rate2) * 0.3
    end
  end


  @spec select_next_comparison([%Object{}], map(), %ComparisonTimsortOptions{}) :: {%Object{}, %Object{}} | nil
  defp select_next_comparison(objects, lookup_table, options) do
    # 아직 비교되지 않은 쌍들 찾기
    uncompared_pairs = for obj1 <- objects,
                          obj2 <- objects,
                          obj1.id < obj2.id,
                          !has_comparison?(lookup_table, obj1.id, obj2.id),
                          do: {obj1, obj2}

    case uncompared_pairs do
      [] -> nil  # 모든 필요한 비교가 완료됨
      pairs ->
        # 정보 이득이 가장 높은 쌍 선택
        Enum.max_by(pairs, fn {obj1, obj2} ->
          calculate_information_gain(obj1, obj2, lookup_table)
        end)
    end
  end

  # 비교 여부를 확인하는 헬퍼 함수 추가
  defp has_comparison?(lookup_table, id1, id2) do
    case {Map.get(lookup_table, id1), Map.get(lookup_table, id2)} do
      {map1, _} when is_map(map1) -> Map.has_key?(map1, id2)
      {_, map2} when is_map(map2) -> Map.has_key?(map2, id1)
      _ -> false
    end
  end

  @spec perform_final_sort([%Object{}], map()) :: [%Object{}]
  defp perform_final_sort(objects, lookup_table) do
    Enum.sort(objects, fn %Object{} = obj1, %Object{} = obj2 ->
      cond do
        obj1.id == obj2.id -> true
        Map.has_key?(lookup_table, obj1.id) and Map.has_key?(lookup_table[obj1.id], obj2.id) ->
          lookup_table[obj1.id][obj2.id]
        Map.has_key?(lookup_table, obj2.id) and Map.has_key?(lookup_table[obj2.id], obj1.id) ->
          not lookup_table[obj2.id][obj1.id]
        true ->
          raise UnknownLookupException,
            message: "Unknown lookup #{obj1.id} #{obj2.id}",
            obj1: obj1,
            obj2: obj2
      end
    end)
  end

  @impl LabelJobType
  def job_results(_options, _job, _label_sessions), do: []

  @impl LabelJobType
  @spec next_group(map(), [%LabelElement{}], [%LabelElement{}]) :: [%Object{}] | :labeling_complete
  def next_group(options, blueprint_elements, session_elements) do
    options = ComparisonTimsortOptions.parse(options)
    objects = Enum.map(blueprint_elements, fn %LabelElement{objects: objects} -> hd(objects) end)
    lookup_table = build_lookup_table(options, session_elements)

    case find_next_group(objects, lookup_table, options) do
      {:labeling_complete, _objects_sorted} -> :labeling_complete
      next_group -> next_group
    end
  end
end
