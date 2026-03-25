[
  # GenStage behaviour callback info is not available in PLT (known dialyxir limitation)
  {"deps/gen_stage/lib/gen_stage.ex", :callback_info_missing},
  # GenStage functions flagged as unknown because of missing callback metadata
  {"lib/ichor/events/ingress.ex", :unknown_function},
  {"lib/ichor/signals/router.ex", :unknown_function}
]
