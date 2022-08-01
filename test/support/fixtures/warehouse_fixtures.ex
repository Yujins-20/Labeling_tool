defmodule Hyacinth.WarehouseFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Hyacinth.Warehouse` context.
  """

  @doc """
  Generate a dataset.
  """
  def dataset_fixture(attrs \\ %{}) do
    {:ok, dataset} =
      attrs
      |> Enum.into(%{
        dataset_type: :root,
        name: "some name"
      })
      |> Hyacinth.Warehouse.create_dataset()

    dataset
  end
end
