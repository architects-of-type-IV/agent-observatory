defmodule AgentPromptProtocol.TemplateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias AgentPromptProtocol.Template

  doctest AgentPromptProtocol.Template

  describe "render/3" do
    test "substitutes a variable" do
      assert Template.render("Hello {{name}}", %{"name" => "Ada"}) == "Hello Ada"
    end

    test "substitutes the same variable everywhere it appears" do
      assert Template.render("{{a}}-{{a}}", %{"a" => "x"}) == "x-x"
    end

    test "substitutes several variables" do
      assert Template.render("{{a}} {{b}}", %{"a" => "1", "b" => "2"}) == "1 2"
    end

    test "stringifies non-string values" do
      assert Template.render("{{n}}", %{"n" => 42}) == "42"
      assert Template.render("{{n}}", %{"n" => :atom}) == "atom"
    end

    test "leaves an empty template alone" do
      assert Template.render("", %{"a" => "1"}) == ""
    end

    test "leaves a template with no placeholders alone" do
      assert Template.render("plain text", %{}) == "plain text"
    end

    test "ignores unused vars" do
      assert Template.render("{{a}}", %{"a" => "1", "unused" => "2"}) == "1"
    end

    test "does not match placeholders with punctuation or spaces" do
      assert Template.render("{{ a }}", %{"a" => "1"}) == "{{ a }}"
      assert Template.render("{{a.b}}", %{"a.b" => "1"}) == "{{a.b}}"
    end

    test "does not recursively expand a substituted value" do
      assert Template.render("{{a}}", %{"a" => "{{b}}", "b" => "boom"}) == "{{b}}"
    end
  end

  describe "render/3 with a missing variable" do
    test "keeps the placeholder and warns by default" do
      log = capture_log(fn -> assert Template.render("{{a}}", %{}) == "{{a}}" end)

      assert log =~ "unresolved vars"
      assert log =~ "a"
    end

    test "keeps quietly with :keep_quiet" do
      log =
        capture_log(fn ->
          assert Template.render("{{a}}", %{}, on_missing: :keep_quiet) == "{{a}}"
        end)

      refute log =~ "unresolved"
    end

    test "drops it with :empty" do
      assert Template.render("x{{a}}y", %{}, on_missing: :empty) == "xy"
    end

    test "raises with :raise" do
      assert_raise KeyError, fn -> Template.render("{{a}}", %{}, on_missing: :raise) end
    end

    test "renders the vars it does have" do
      capture_log(fn ->
        assert Template.render("{{a}}-{{b}}", %{"a" => "1"}) == "1-{{b}}"
      end)
    end
  end

  describe "variables/1" do
    test "lists distinct names in order of first use" do
      assert Template.variables("{{b}} {{a}} {{b}}") == ["b", "a"]
    end

    test "is empty for a template with no placeholders" do
      assert Template.variables("nothing here") == []
    end
  end

  describe "unresolved/2" do
    test "lists only what is missing" do
      assert Template.unresolved("{{a}} {{b}}", %{"a" => 1}) == ["b"]
    end

    test "is empty when everything is supplied" do
      assert Template.unresolved("{{a}}", %{"a" => 1}) == []
    end

    test "treats an explicit nil as supplied" do
      assert Template.unresolved("{{a}}", %{"a" => nil}) == []
    end

    test "defaults to no vars at all" do
      assert Template.unresolved("{{a}} {{b}}") == ["a", "b"]
    end
  end
end
