defmodule Ichor.Repo.Migrations.RenameWorkshopTeamJsonKeys do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE workshop_teams
    SET agents = (
      SELECT json_group_array(
        json_object(
          'id', json_extract(value, '$.slot'),
          'agent_type_id', json_extract(value, '$.agent_type_id'),
          'name', json_extract(value, '$.name'),
          'capability', json_extract(value, '$.capability'),
          'model', json_extract(value, '$.model'),
          'permission', json_extract(value, '$.permission'),
          'persona', json_extract(value, '$.persona'),
          'file_scope', json_extract(value, '$.file_scope'),
          'quality_gates', json_extract(value, '$.quality_gates'),
          'tools', json_extract(value, '$.tools'),
          'x', json_extract(value, '$.canvas_x'),
          'y', json_extract(value, '$.canvas_y')
        )
      )
      FROM json_each(workshop_teams.agents)
    )
    WHERE agents IS NOT NULL AND agents != '[]'
    """)

    execute("""
    UPDATE workshop_teams
    SET spawn_links = (
      SELECT json_group_array(
        json_object(
          'from', json_extract(value, '$.from_slot'),
          'to', json_extract(value, '$.to_slot')
        )
      )
      FROM json_each(workshop_teams.spawn_links)
    )
    WHERE spawn_links IS NOT NULL AND spawn_links != '[]'
    """)

    execute("""
    UPDATE workshop_teams
    SET comm_rules = (
      SELECT json_group_array(
        json_object(
          'from', json_extract(value, '$.from_slot'),
          'to', json_extract(value, '$.to_slot'),
          'policy', json_extract(value, '$.policy'),
          'via', json_extract(value, '$.via_slot')
        )
      )
      FROM json_each(workshop_teams.comm_rules)
    )
    WHERE comm_rules IS NOT NULL AND comm_rules != '[]'
    """)
  end

  def down do
    execute("""
    UPDATE workshop_teams
    SET agents = (
      SELECT json_group_array(
        json_object(
          'slot', json_extract(value, '$.id'),
          'agent_type_id', json_extract(value, '$.agent_type_id'),
          'name', json_extract(value, '$.name'),
          'capability', json_extract(value, '$.capability'),
          'model', json_extract(value, '$.model'),
          'permission', json_extract(value, '$.permission'),
          'persona', json_extract(value, '$.persona'),
          'file_scope', json_extract(value, '$.file_scope'),
          'quality_gates', json_extract(value, '$.quality_gates'),
          'tools', json_extract(value, '$.tools'),
          'canvas_x', json_extract(value, '$.x'),
          'canvas_y', json_extract(value, '$.y')
        )
      )
      FROM json_each(workshop_teams.agents)
    )
    WHERE agents IS NOT NULL AND agents != '[]'
    """)

    execute("""
    UPDATE workshop_teams
    SET spawn_links = (
      SELECT json_group_array(
        json_object(
          'from_slot', json_extract(value, '$.from'),
          'to_slot', json_extract(value, '$.to')
        )
      )
      FROM json_each(workshop_teams.spawn_links)
    )
    WHERE spawn_links IS NOT NULL AND spawn_links != '[]'
    """)

    execute("""
    UPDATE workshop_teams
    SET comm_rules = (
      SELECT json_group_array(
        json_object(
          'from_slot', json_extract(value, '$.from'),
          'to_slot', json_extract(value, '$.to'),
          'policy', json_extract(value, '$.policy'),
          'via_slot', json_extract(value, '$.via')
        )
      )
      FROM json_each(workshop_teams.comm_rules)
    )
    WHERE comm_rules IS NOT NULL AND comm_rules != '[]'
    """)
  end
end
