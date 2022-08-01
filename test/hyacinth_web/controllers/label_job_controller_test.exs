defmodule HyacinthWeb.LabelJobControllerTest do
  use HyacinthWeb.ConnCase

  import Hyacinth.LabelingFixtures

  @create_attrs %{label_type: :classification, name: "some name"}
  @update_attrs %{label_type: :classification, name: "some updated name"}
  @invalid_attrs %{label_type: nil, name: nil}

  describe "index" do
    test "lists all label_jobs", %{conn: conn} do
      conn = get(conn, Routes.label_job_path(conn, :index))
      assert html_response(conn, 200) =~ "Listing Label jobs"
    end
  end

  describe "new label_job" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.label_job_path(conn, :new))
      assert html_response(conn, 200) =~ "New Label job"
    end
  end

  describe "create label_job" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, Routes.label_job_path(conn, :create), label_job: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == Routes.label_job_path(conn, :show, id)

      conn = get(conn, Routes.label_job_path(conn, :show, id))
      assert html_response(conn, 200) =~ "Show Label job"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.label_job_path(conn, :create), label_job: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Label job"
    end
  end

  describe "edit label_job" do
    setup [:create_label_job]

    test "renders form for editing chosen label_job", %{conn: conn, label_job: label_job} do
      conn = get(conn, Routes.label_job_path(conn, :edit, label_job))
      assert html_response(conn, 200) =~ "Edit Label job"
    end
  end

  describe "update label_job" do
    setup [:create_label_job]

    test "redirects when data is valid", %{conn: conn, label_job: label_job} do
      conn = put(conn, Routes.label_job_path(conn, :update, label_job), label_job: @update_attrs)
      assert redirected_to(conn) == Routes.label_job_path(conn, :show, label_job)

      conn = get(conn, Routes.label_job_path(conn, :show, label_job))
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "renders errors when data is invalid", %{conn: conn, label_job: label_job} do
      conn = put(conn, Routes.label_job_path(conn, :update, label_job), label_job: @invalid_attrs)
      assert html_response(conn, 200) =~ "Edit Label job"
    end
  end

  describe "delete label_job" do
    setup [:create_label_job]

    test "deletes chosen label_job", %{conn: conn, label_job: label_job} do
      conn = delete(conn, Routes.label_job_path(conn, :delete, label_job))
      assert redirected_to(conn) == Routes.label_job_path(conn, :index)

      assert_error_sent 404, fn ->
        get(conn, Routes.label_job_path(conn, :show, label_job))
      end
    end
  end

  defp create_label_job(_) do
    label_job = label_job_fixture()
    %{label_job: label_job}
  end
end