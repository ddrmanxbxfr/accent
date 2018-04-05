defmodule Accent.Plugs.MovementContextParser do
  use Plug.Builder

  alias Accent.{Repo, Document}
  alias Accent.Scopes.Document, as: DocumentScope
  alias Langue.Formatter.Strings.Parser, as: StringsParser
  alias Langue.Formatter.Rails.Parser, as: RailsParser
  alias Langue.Formatter.Json.Parser, as: JsonParser
  alias Langue.Formatter.SimpleJson.Parser, as: SimpleJsonParser
  alias Langue.Formatter.Es6Module.Parser, as: Es6ModuleParser
  alias Langue.Formatter.Android.Parser, as: AndroidParser
  alias Langue.Formatter.JavaProperties.Parser, as: JavaPropertiesParser
  alias Langue.Formatter.JavaPropertiesXml.Parser, as: JavaPropertiesXmlParser
  alias Langue.Formatter.Gettext.Parser, as: GettextParser
  alias Movement.Context

  plug(:validate_params)
  plug(:assign_document_parser)
  plug(:assign_document_path)
  plug(:assign_document_format)
  plug(:assign_document_locale)
  plug(:assign_movement_context)
  plug(:assign_movement_document)
  plug(:assign_movement_entries)

  def validate_params(conn = %{params: %{"document_format" => _format, "file" => _file, "language" => _language}}, _), do: conn
  def validate_params(conn, _), do: conn |> send_resp(:unprocessable_entity, "file, language and document_format are required") |> halt

  def assign_document_parser(conn = %{params: %{"document_format" => document_format}}, _) do
    case parser_from_format(document_format) do
      {:ok, parser} -> assign(conn, :document_parser, parser)
      {:error, _reason} -> conn |> send_resp(:unprocessable_entity, "document_format is invalid") |> halt
    end
  end

  def assign_document_locale(conn = %{params: %{"language" => language}}, _) do
    assign(conn, :document_locale, language)
  end

  def assign_document_format(conn = %{params: %{"document_format" => format}}, _) do
    assign(conn, :document_format, format)
  end

  def assign_document_path(conn = %{params: %{"document_path" => path}}, _) when path !== "" and not is_nil(path) do
    assign(conn, :document_path, extract_path_from_filename(path))
  end

  def assign_document_path(conn = %{params: %{"file" => file}}, _) do
    assign(conn, :document_path, extract_path_from_filename(file.filename))
  end

  def assign_movement_context(conn, _) do
    assign(conn, :movement_context, %Context{})
  end

  def assign_movement_document(conn = %{assigns: %{project: project, movement_context: context, document_path: path, document_format: format}}, _opts) do
    document =
      Document
      |> DocumentScope.from_path(path)
      |> DocumentScope.from_project(project.id)
      |> Repo.one()

    case document do
      nil ->
        context = Context.assign(context, :document, %Document{project_id: project.id, path: path, format: format})
        assign(conn, :movement_context, context)

      _ ->
        document = %{document | format: format}
        context = Context.assign(context, :document, document)
        assign(conn, :movement_context, context)
    end
  end

  def assign_movement_entries(conn = %{assigns: %{movement_context: context}, params: %{"file" => file}}, _) do
    render = File.read!(file.path)

    conn
    |> serializer_result(render)
    |> case do
      %Langue.Formatter.ParserResult{entries: entries, top_of_the_file_comment: comment, header: header} ->
        document = %{context.assigns[:document] | top_of_the_file_comment: comment, header: header}

        context =
          context
          |> Context.assign(:document, document)
          |> Context.assign(:document_update, %{top_of_the_file_comment: comment, header: header})
          |> Map.put(:render, render)
          |> Map.put(:entries, entries)

        assign(conn, :movement_context, context)

      {:error, :invalid_file} ->
        conn |> send_resp(:unprocessable_entity, "file cannot be parsed") |> halt
    end
  end

  defp serializer_result(conn, render) do
    conn.assigns[:document_parser].(%Langue.Formatter.SerializerResult{render: render})
  catch
    _ -> {:error, :invalid_file}
  end

  defp extract_path_from_filename(filename) do
    filename
    |> String.split(".", parts: 2)
    |> Enum.at(0)
  end

  defp parser_from_format("strings"), do: {:ok, &StringsParser.parse/1}
  defp parser_from_format("rails_yml"), do: {:ok, &RailsParser.parse/1}
  defp parser_from_format("json"), do: {:ok, &JsonParser.parse/1}
  defp parser_from_format("simple_json"), do: {:ok, &SimpleJsonParser.parse/1}
  defp parser_from_format("android_xml"), do: {:ok, &AndroidParser.parse/1}
  defp parser_from_format("es6_module"), do: {:ok, &Es6ModuleParser.parse/1}
  defp parser_from_format("java_properties"), do: {:ok, &JavaPropertiesParser.parse/1}
  defp parser_from_format("java_properties_xml"), do: {:ok, &JavaPropertiesXmlParser.parse/1}
  defp parser_from_format("gettext"), do: {:ok, &GettextParser.parse/1}
  defp parser_from_format(_), do: {:error, :unknown_parser}
end