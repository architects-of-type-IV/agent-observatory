defmodule Ichor.Architecture.BoundaryAudit do
  @moduledoc """
  Non-mutating application boundary audit used to track post-umbrella cleanliness.
  """

  @host_globs ["lib/**/*.ex", "test/**/*.exs"]

  @direct_ash_pattern ~r/\bAsh\.(create|create!|update|update!|destroy|destroy!|read|read!|get|get!)\b/
  @swarm_pattern ~r/\bSwarmMonitor\b|\bswarm_state\b|\bswarm_[a-z0-9_]+\b/

  @resource_modules []

  @domain_modules []

  @spec run() :: map()
  def run do
    files = host_files()

    %{
      direct_ash: scan(files, @direct_ash_pattern),
      resource_calls: scan(files, resource_pattern()),
      swarm_terms: scan(files, @swarm_pattern),
      domain_calls: scan(files, domain_pattern())
    }
  end

  @spec print_report(map(), keyword()) :: :ok
  def print_report(report, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)

    IO.puts("Boundary Audit")
    IO.puts("")
    print_section("Direct Ash API usage", report.direct_ash)
    print_section("Direct resource module references", report.resource_calls)
    print_section("Legacy swarm terminology", report.swarm_terms)
    print_section("Domain-level references", report.domain_calls, summarize_only: true)

    findings = report.direct_ash ++ report.resource_calls ++ report.swarm_terms

    IO.puts("")

    cond do
      findings == [] ->
        IO.puts("Audit result: clean")

      strict? ->
        IO.puts("Audit result: findings present")
        raise "boundary audit failed in strict mode"

      true ->
        IO.puts("Audit result: findings present")
    end

    :ok
  end

  defp host_files do
    @host_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&audit_support_file?/1)
    |> Enum.sort()
  end

  defp scan(files, regex) do
    Enum.flat_map(files, fn path ->
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} ->
        Regex.match?(regex, line) and not ignorable_line?(line)
      end)
      |> Enum.map(fn {line, line_no} ->
        %{file: path, line: line_no, text: String.trim(line)}
      end)
    end)
  end

  defp audit_support_file?(path) do
    String.ends_with?(path, "lib/ichor/architecture/boundary_audit.ex") or
      String.ends_with?(path, "lib/mix/tasks/ichor.boundary_audit.ex")
  end

  defp ignorable_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      String.starts_with?(trimmed, "#") or
      String.starts_with?(trimmed, "- ") or
      String.starts_with?(trimmed, "@moduledoc") or
      String.starts_with?(trimmed, "@shortdoc") or
      quoted_only?(trimmed)
  end

  defp quoted_only?(line) do
    String.starts_with?(line, "\"") or String.starts_with?(line, "'")
  end

  defp print_section(title, findings, opts \\ []) do
    summarize_only? = Keyword.get(opts, :summarize_only, false)

    IO.puts("#{title}: #{length(findings)}")

    unless summarize_only? do
      findings
      |> Enum.take(20)
      |> Enum.each(fn finding ->
        IO.puts("  #{finding.file}:#{finding.line} #{finding.text}")
      end)

      if length(findings) > 20 do
        IO.puts("  ... #{length(findings) - 20} more")
      end
    end

    IO.puts("")
  end

  defp resource_pattern, do: build_pattern(@resource_modules)
  defp domain_pattern, do: build_pattern(@domain_modules)

  # @resource_modules and @domain_modules are [] placeholders. When populated,
  # the non-empty branch handles regex construction.
  @dialyzer {:nowarn_function, build_pattern: 1}
  defp build_pattern(modules) do
    case modules do
      [] ->
        ~r/\A\z/

      _ ->
        escaped = Enum.map_join(modules, "|", &Regex.escape/1)
        Regex.compile!("\\b(?:#{escaped})\\b")
    end
  end
end
