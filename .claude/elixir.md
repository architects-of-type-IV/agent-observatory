<GUIDELINES language="elixir">
<CODE-GUIDELINES language="elixir">
# Coding Guidelines for Elixir
Guidelines for writing idiomatic Elixir code, focusing on design, readability, and prohibited patterns, to ensure that the code is clean, maintainable, and follows best practices.

## Elixir Version 1.19

### Design:
- **EX and HEEX:** Separate EX (Elixir) and HEEX (HTML Elixir) files for better organization and maintainability. Use EX files for business logic and HEEX files for HTML templates. Keep modules small. Components should be self-contained and reusable. Use defdelegate pattern.
- **Small, Focused Functions:** Break the solution into small, composable functions that each serve a single, clear purpose. Avoid monolithic functions – smaller pure functions are easier to understand, test, and reuse.
- **Pure Functions by Default:** Write pure functions (no side effects or mutable state) wherever possible. Only introduce side effects (like I/O or manipulating process state) at defined boundaries of the application (e.g. in specific modules or callback functions dedicated to I/O or process management).
- **Clear Input Handling:** Use pattern matching and guards to validate inputs and handle edge cases up front. Functions should explicitly handle invalid or unexpected inputs rather than failing implicitly. This makes the code more robust and its intent clearer.
- **Minimal Side Effects:** Keep state and side effects isolated. If state must be shared or mutated, consider using an appropriate OTP abstraction (like a GenServer) but **only** when necessary. Avoid hiding side effects in the middle of business logic; push them to the edges (for example, perform database or file operations in dedicated functions or processes, not scattered throughout logic).
- **Idiomatic Functional Style:** Utilize Elixir’s standard library (`Enum`, `Stream`, etc.) and functional paradigms for clarity. Prefer high-level abstractions over low-level loops; for instance, use `Enum.map/2` or list comprehensions for iteration, and `Stream` for lazy processing of large or infinite sequences to conserve memory. Use the pipeline operator (`|>`) to make transformations readable, but break up or comment pipelines that become overly long or complex.
- **Appropriate Concurrency Constructs:** Only introduce concurrent processes when the problem truly requires it (e.g. handling multiple tasks simultaneously or maintaining independent state). Do **not** organize code into processes arbitrarily. When concurrency is needed, use OTP patterns and modules (`Task`, `GenServer`, `Agent`, etc.) in an idiomatic way. For short-lived asynchronous tasks, prefer `Task.async/await` (or `Task.Supervisor`) rather than spawning raw processes, so that failures can be supervised and handled.
- **Scoped Supervision Trees:** Design a proper supervision tree for any long-lived processes. Each GenServer/Agent process should be started under a Supervisor with an appropriate restart strategy, rather than being spawned unsupervised. This ensures fault tolerance and clarity in how processes are linked and restarted on errors.
- **Clear Process Responsibilities:** If using OTP processes, give each its own well-defined responsibility and API. For example, a GenServer should encapsulate its state and expose a clean public API (functions that call `GenServer.call/cast`). Do not require callers to know about the process internals. This separation of concerns makes it easier to reason about process boundaries.
- **Explicit Configuration:** Use explicit parameters or function arguments for configuration rather than relying on implicit global state. If writing a library or reusable component, avoid pulling values from application config (e.g. `Application.get_env`) inside core functions – instead, accept options or defaults as inputs. This keeps modules flexible and free of hidden dependencies on global configuration.

### Readability:

- **Descriptive Naming:** Choose clear, descriptive names for modules, functions, and variables. Names should reveal intent (e.g. `calculate_total/2` instead of `foo/2`). This reduces the need for comments and makes the code self-documenting.
- **Clarity Over Cleverness:** Prioritize straightforward, readable code over overly clever or terse solutions. Use expressions and control-flow that other Elixir developers would expect. For example, use pattern matching in function heads or simple case statements for branching logic rather than obscure one-liners.
- **Avoid Deep Nesting:** Prevent deeply nested `if/else`, `case`, or `with` blocks which can be hard to follow. Instead, use guard clauses, multiple function clauses, or early returns (e.g. pattern match a {:error, reason} tuple and handle it early) to keep the happy path less indented. If you find code is nesting multiple levels of logic, refactor into smaller helper functions to flatten the structure.
- **Limited Pipeline Length:** Use the pipeline operator to clarify successive transformations, but avoid pipelines that are too long or complex (for instance, a pipeline of 10 steps with anonymous functions can hurt readability). It’s acceptable to break a complex pipeline into intermediate variables or separate functions for clarity.
- **Self-Documenting Code & Comments:** Strive to make the code self-explanatory through clear logic and naming. Write **minimal comments**, and only when necessary to explain why (the reasoning or intent), not what the code is doing. Over-commenting (especially restating obvious code logic) is discouraged. Instead of in-line comments for obvious steps, consider using module or function documentation (`@moduledoc`, `@doc`) to provide context or examples for how to use the code.
- **Consistent Style:** Follow Elixir’s standard style guidelines (the community conventions and the formatter). Ensure proper indentation (2 spaces), spacing, and line breaks to enhance readability. Organize the code logically (related functions grouped together, blank lines separating different sections). Use idiomatic constructs (e.g. `with` for linear happy-path with multiple pattern matches, when appropriate) in a way that readers find familiar.
- **Boolean Clarity:** Avoid “boolean blindness” – do not use multiple boolean flags or vague conditionals that make it unclear what state the system is in. If a function takes several booleans to alter its behavior, that’s a sign to refactor (for example, use an atom or an enumerated type to represent modes or states, or split into separate functions for each mode). This makes the code’s intention much clearer than `func(true, false, true)` style calls.
- **Structured Data Over Primitives:** Use structs or maps to represent complex data rather than passing around primitive values in tuples or lists without context. For example, if dealing with user information or configuration, define a struct or use a map with named keys instead of a long list of parameters. This enhances readability by giving meaning to data through keys and types.

### Prohibited Patterns:

- **Unnecessary Macros:** Do not use macros when a plain function would suffice. Overusing or misusing macros is a major anti-pattern in Elixir – it makes code harder to understand and maintain. Only reach for `defmacro` for metaprogramming tasks that cannot be solved with regular functions. In general, avoid code that is “clever” at compile-time at the expense of clarity at runtime.
- **Process for Code Organization:** **Never** create a process (e.g. a GenServer or Agent) solely to organize code or hold state that could be returned from a function. Tying basic logic to a process call (like using a GenServer just to perform calculations sequentially) introduces unnecessary complexity and bottlenecks. Use modules and pure functions for organization; only use processes to model concurrency, shared mutable state, or side-effect management when absolutely required.
- **Agent/GenServer Misuse (Agent Obsession):** Avoid spreading process state access across the codebase. All interactions with a GenServer or Agent should go through a dedicated module API. Do not read from or write to an OTP process from arbitrary modules (no global Agent where any code grabs or updates state). This “Agent obsession” (scattered process interface) leads to tightly coupled code and unclear ownership of state. Instead, centralize process interaction in one place and pass data explicitly to other functions that need it.
- **Tightly-Coupled Processes:** Do not design processes that are highly dependent on each other’s internal implementation or timing. Processes should communicate via well-defined messages or calls, and each process should be independently understandable. For example, avoid having one GenServer call functions deep inside another GenServer’s module in a way that intertwines their logic. Such coupling makes the system fragile. Keep process interfaces decoupled and use supervision/restarts to handle failures rather than manual coordination between processes.
- **Unsupervised Long-Lived Processes:** Do not spawn long-running processes outside of a supervision tree. Any persistent process (GenServer, Agent, Task that runs indefinitely, etc.) must be part of a Supervisor hierarchy so crashes can be isolated and recovered from. Spawning unsupervised processes (via `spawn`, `Task.start`, or `Task.async` without supervision) for long-lived tasks is an anti-pattern. Always either return the process to the caller to supervise, or use a Supervisor/DynamicSupervisor to start it.
- **Exceptions for Control Flow:** Do not use `try/rescue` or throw/catch to control normal program flow. Using exceptions for expected conditions (like using a rescue to check if a file exists, or to break out of nested loops) is discouraged. Instead, rely on functions that return `{:ok, value}`/`{:error, reason}` tuples or other tagged outcomes for error handling. Reserve exceptions for truly unexpected errors or programmer mistakes. For example, use `File.read/1` returning `{:error, reason}` instead of rescuing an exception from `File.read!`.
- **Deeply Nested Logic:** Avoid code with multiple layers of nested `case/cond/with` expressions or anonymous function callbacks. This goes hand-in-hand with the readability guideline above – deeply nested logic is hard to follow and maintain. If you have a `with` with a complex `else` clause handling many error cases, or several levels of indentation, refactor by handling some errors earlier or splitting the logic into smaller functions. Each function should ideally have a single level of significant indentation for the happy path.
- **Long Parameter Lists:** Do not define functions with excessively long parameter lists (a classic code smell). If a function has more than about 4 parameters, consider grouping related parameters into a map or struct, or splitting the function into smaller functions that each take a subset of those parameters. Long parameter lists are hard to read and easy to misuse. Instead, passing a map/struct with named fields can make the call site much more readable and reduce mistakes.
- **Dynamic Atom Creation:** Never create atoms from arbitrary or user-provided strings at runtime (e.g. avoid `String.to_atom/1` on external input). This can exhaust the atom table and crash the system. If you need to map strings to atoms, use a safe mapping or a known limited set of atoms. In general, prefer strings or existing atoms for keys unless you have a very good reason to generate new atoms (and if so, ensure they are bounded in quantity).
- **Namespace Trespassing:** When writing libraries (or even internal code), do not define modules inside namespaces you don’t own. For example, if your application or library is named `MyApp`, avoid defining modules that start with another app’s name or a generic name (like `Plug.Auth` inside your code when you are not part of the Plug library). Always use your project’s umbrella namespace (e.g. `MyApp.*`) for your modules to prevent name collisions and clarify ownership. Similarly, avoid using deprecated modules or approaches (such as the old `:dict` module) when modern equivalents (like `Map`) exist.
- **Mixing Unrelated Logic:** Don’t pack unrelated functionalities into different clauses of the same function. Each multi-clause function should handle variations of one responsibility (for example, pattern matching on different shapes of input for the same conceptual operation). If you find a function clause doing something entirely different from another clause (different business logic), split them into separate functions or modules. This improves code organization and follow the Single Responsibility Principle at the function level.

## Output Requirements:

- **Complete and Functional:** The final output should be a complete Elixir solution that fulfills all the given requirements or problem description. It must be **idiomatic** and **production-quality**, meaning it not only works correctly but is designed and written following the best practices above.
- **Code Only (Unless Specified):** Provide the solution as properly formatted Elixir code. Unless explicitly asked for an explanation, the answer should primarily consist of code (enclosed in Markdown triple backticks with an `elixir` language tag for clarity). Avoid extraneous commentary in the output; any explanation of the code’s behavior should be conveyed through clear naming and, if necessary, concise comments or documentation within the code.
- **Formatting and Style:** The code should be formatted with Elixir’s formatter (two-space indentation, appropriate line breaks, etc.) so that it’s immediately readable. Ensure there are no compiler or credo warnings. Module and function definitions should be correctly structured, and public functions should include @spec typespecs and @doc documentation when appropriate to demonstrate proper API usage.
- **Testing and Examples:** If the prompt or task includes example inputs/outputs or requires demonstrating the solution, include either an `ExUnit` test module or a simple example of calling the functions in the output. These examples or tests should also follow the above idiomatic style. (If the problem statement does not require showing usage, you can omit explicit tests but make sure the solution could be easily tested.)
- **Robustness:** The solution should handle edge cases gracefully (per the problem requirements) and avoid any of the prohibited anti-patterns listed. Even though only the code is output, it’s expected that the code has been designed with consideration for performance and fault tolerance (e.g. tail-recursive functions for heavy recursion, using Streams for large data handling, etc., as appropriate). In other words, the output should not only solve the problem but do so in a way that could be trusted in a production environment, adhering to Elixir’s idiomatic conventions.
</CODE-GUIDELINES>
<EXAMPLES language="elixir">
<EXAMPLE language="elixir" type="library">
# Example Elixir library: 

Currency Conversion and Exchange Rate Cache

- This library showcases idiomatic Elixir code that avoids anti-patterns.
- It includes pure logic, GenServer process cache, batch stream processing,
- Showcases LLM agents with LangChain, and a supervision tree.


## MODULE 1: Business Logic (Pure)

```elixir
  defmodule FxCalc.Converter do
    @moduledoc """
    Provides functions for converting amounts between currencies.
    Assumes exchange rates are passed in as arguments.
    """
  
    @spec convert(number(), number()) :: number()
    def convert(amount, rate) when amount >= 0 and rate > 0 do
      Float.round(amount * rate, 2)
    end
  end
```

## MODULE 2: Rate Cache (Supervised GenServer)

```elixir
defmodule FxCalc.RateCache do
  @moduledoc """
  Caches exchange rates with expiration, using GenServer.
  Should be started under a supervision tree.
  """

  use GenServer

  @type state :: %{required(String.t()) => {number(), DateTime.t()}}
  @ttl_seconds 300

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state}

  @spec put_rate(String.t(), number()) :: :ok
  def put_rate(pair, rate) do
    GenServer.cast(__MODULE__, {:put, pair, rate})
  end

  @spec get_rate(String.t()) :: {:ok, number()} | :not_found
  def get_rate(pair) do
    GenServer.call(__MODULE__, {:get, pair})
  end

  @impl true
  def handle_cast({:put, pair, rate}, state) do
    now = DateTime.utc_now()
    {:noreply, Map.put(state, pair, {rate, now})}
  end

  @impl true
  def handle_call({:get, pair}, _from, state) do
    case Map.get(state, pair) do
      {rate, ts} when not expired?(ts) -> {:reply, {:ok, rate}, state}
      _ -> {:reply, :not_found, Map.delete(state, pair)}
    end
  end

  defp expired?(timestamp) do
    DateTime.diff(DateTime.utc_now(), timestamp) > @ttl_seconds
  end
end
```

## MODULE 3: Batch Processor with Stream

```elixir
defmodule FxCalc.BatchProcessor do
  @moduledoc """
  Processes a CSV stream of amounts to be converted using a given rate.
  Demonstrates safe streaming, parsing, and transformation.
  """

  alias FxCalc.Converter

  @spec process_file(Path.t(), number()) :: Enumerable.t()
  def process_file(path, rate) do
    path
    |> File.stream!([], :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&parse_and_convert(&1, rate))
  end

  defp parse_and_convert(line, rate) do
    case Float.parse(line) do
      {amount, ""} -> {:ok, Converter.convert(amount, rate)}
      _ -> {:error, :invalid_line}
    end
  end
end
```

## MODULE 4: LangChain LLM Agent

```elixir
defmodule FxCalc.Agent.CurrencyAdvisor do
  @moduledoc """
  LLM agent that advises on FX decisions using LangChain.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.Prompts.PromptTemplate
  alias LangChain.LLMs.ChatOpenAI

  @spec advise(String.t()) :: {:ok, String.t()} | {:error, any()}
  def advise(query) do
    llm = %ChatOpenAI{model: "gpt-4", temperature: 0.2}

    prompt =
      PromptTemplate.new!(
        template: "You are an FX advisor. A user asked: {{question}}",
        inputs: %{question: query}
      )

    chain = %LLMChain{llm: llm, prompt: prompt}

    LLMChain.run(chain)
  end
end
```

## MODULE 5: LangChain Multi-Agent Planner

```elixir
defmodule FxCalc.Agent.MacroPlanner do
  @moduledoc """
  LLM agent that plans multi-agent behavior for FX strategy.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.Prompts.FewShotPromptTemplate
  alias LangChain.LLMs.ChatOpenAI

  @spec plan(String.t()) :: {:ok, String.t()} | {:error, any()}
  def plan(goal) do
    examples = [
      %{"goal" => "Convert USD to EUR", "action" => "Call CurrencyAdvisor then Converter"},
      %{"goal" => "Compare GBP vs JPY", "action" => "Call CurrencyAdvisor then RateCache"}
    ]

    prompt =
      FewShotPromptTemplate.new!(
        input_variables: ["goal"],
        examples: examples,
        example_template: "Goal: {{goal}}\nAction: {{action}}",
        prefix: "Plan the correct agent flow for this FX goal.",
        suffix: "Goal: {{goal}}\nAction:",
        input: %{goal: goal}
      )

    llm = %ChatOpenAI{model: "gpt-4", temperature: 0.3}
    chain = %LLMChain{llm: llm, prompt: prompt}

    LLMChain.run(chain)
  end
end
```

## MODULE 6: Agent Coordinator

```elixir
defmodule FxCalc.Agent.Orchestrator do
  @moduledoc """
  Coordinates multiple agents to retrieve rate, perform conversion, and query LLM commentary.
  """

  alias FxCalc.{RateCache, Converter}
  alias FxCalc.Agent.CurrencyAdvisor

  @spec process(String.t(), number()) :: {:ok, map()} | {:error, any()}
  def process("USD_EUR", amount) do
    with {:ok, rate} <- RateCache.get_rate("USD_EUR"),
         converted <- Converter.convert(amount, rate),
         {:ok, commentary} <- CurrencyAdvisor.advise("Convert #{amount} USD to EUR at #{rate}") do
      {:ok, %{converted: converted, commentary: commentary}}
    else
      _ -> {:error, :unable_to_process}
    end
  end
end
```

## MODULE 7: Supervision Tree (Application Entry)

```elixir
defmodule FxCalc.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {FxCalc.RateCache, []}
    ]

    opts = [strategy: :one_for_one, name: FxCalc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```
</EXAMPLE>
<EXAMPLE language="elixir" type="modules">
# Example Elixir modules:

## EXAMPLE 1: Safe File Reader with Error Tuple Return

Purpose: Read a config file without crashing the app.

```elixir
defmodule MyApp.ConfigReader do
  @moduledoc """
  Safely reads configuration from a file and parses it as JSON.
  """

  @spec read_json_file(String.t()) :: {:ok, map()} | {:error, atom()}
  def read_json_file(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decoded}
    else
      {:error, _} = err -> err
    end
  end
end
```

## EXAMPLE 2: Scoped OTP Process With Supervision

Purpose: Cache config in memory with safe GenServer encapsulation.

```elixir
defmodule MyApp.ConfigCache do
  @moduledoc """
  Caches configuration values in memory.

  Must be started under supervision.(application.ex)

    children = [
        {MyApp.ConfigCache, []}
    ]

  """

  use GenServer

  @type state :: %{optional(atom()) => any()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state}

  @spec put(atom(), any()) :: :ok
  def put(key, value), do: GenServer.cast(__MODULE__, {:put, key, value})

  @spec get(atom()) :: any()
  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end
end

```

## EXAMPLE 3: Pure, Composable Business Logic Module

Purpose: Calculate total order price with tax and discount, pure logic only.

```elixir
defmodule Shop.OrderCalculator do
  @moduledoc """
  Provides functions to calculate the total order cost, including tax and discount.
  """

  @spec total_cost(number(), number(), number()) :: number()
  def total_cost(subtotal, tax_rate, discount_rate)
      when subtotal >= 0 and tax_rate >= 0 and discount_rate >= 0 do
    subtotal
    |> apply_discount(discount_rate)
    |> apply_tax(tax_rate)
  end

  defp apply_discount(amount, rate), do: amount * (1 - rate)
  defp apply_tax(amount, rate), do: amount * (1 + rate)
end

```
</EXAMPLE>
</EXAMPLES>
</GUIDELINES>
