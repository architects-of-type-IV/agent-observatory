exclude = if System.find_executable("tmux"), do: [], else: [tmux: true]

if exclude != [] do
  IO.puts("tmux not found on PATH — skipping integration tests tagged :tmux")
end

ExUnit.start(exclude: exclude)
