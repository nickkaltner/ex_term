defmodule ExTerm.Console.StringTracker do
  @moduledoc false

  # special module to do simple compound string operations on the console.
  # this includes:
  #
  # - put_string_rows
  # - insert_string_rows

  use MatchSpec

  alias ExTerm.Console
  alias ExTerm.Console.Cell
  require Console

  @enforce_keys [
    :insertion,
    :console,
    :style,
    :cursor,
    :old_cursor,
    :layout,
    :first_updated,
    :last_updated,
    :last_cell
  ]
  defstruct @enforce_keys ++ [updates: []]

  @type t :: %__MODULE__{
          insertion: nil | pos_integer(),
          console: Console.t(),
          style: Style.t(),
          cursor: Console.location(),
          old_cursor: Console.location(),
          layout: Console.location(),
          first_updated: Console.location(),
          last_updated: Console.location(),
          last_cell: Console.location()
        }

  @spec new(Console.t(), nil | pos_integer()) :: t
  def new(console, insertion \\ nil) do
    [cursor: old_cursor, layout: layout, style: style] =
      Console.get_metadata(console, [:cursor, :layout, :style])

    new_cursor = if insertion, do: {insertion, 1}, else: old_cursor
    last_cell = Console.last_cell(console)

    %__MODULE__{
      insertion: insertion,
      cursor: new_cursor,
      old_cursor: old_cursor,
      style: style,
      console: console,
      layout: layout,
      first_updated: new_cursor,
      last_updated: new_cursor,
      last_cell: last_cell
    }
  end

  @spec put_string_rows(t(), String.t()) :: t()
  def put_string_rows(tracker = %{cursor: {row, _}, insertion: nil}, string) do
    # NB: don't cache the number of rows.  Row length should be fixed once set.
    columns = Console.columns(tracker.console, row)
    case put_string_row(tracker, columns, string) do
      # exhausted the row without finishing the string
      {updated_tracker, leftover} ->
        put_string_rows(%{updated_tracker | cursor: {row + 1, 1}}, leftover)

      done ->
        done
    end
  end

  @spec insert_string_rows(t(), String.t()) :: t()
  def insert_string_rows(tracker = %{insertion: row}, string) when is_integer(row) do
    # NB: don't cache the number of rows.  Row length should be fixed once set.
    columns = Console.columns(tracker.console, row)
    case put_string_row(tracker, columns, string) do
      done = %{updates: [{{last_row, _}, _} | _]} ->
        # figure out how many rows we need to move.  This is determined by the number
        # of rows in the update.  Let's assume that it is the row of the first item.

        move_distance = last_row - row + 1

        done
        |> pad_last_row(columns)
        |> move_succeeding_rows(row, move_distance)
        |> update_cursor(tracker.old_cursor, row, move_distance)
        |> update_insert()
    end
  end

  def put_string_row(
        tracker = %{
          cursor: {row, column},
          console: console,
          last_cell: {last_row, last_cell_column}
        },
        columns,
        string
      )
      when column === columns + 1 do
    if row === last_row do
      # if we're at the end of the tracker, be sure to add a new row, first
      new_row = row + 1
      {_, columns} = tracker.layout
      Console.insert(console, Console.make_blank_row(new_row, columns))
      {%{tracker | last_cell: {new_row, last_cell_column}}, string}
    else
      {tracker, string}
    end
  end

  def put_string_row(tracker, columns, "\t" <> string) do
    {hard_tab(tracker, columns), string}
  end

  def put_string_row(tracker, _columns, "\r\n" <> string) do
    {hard_return(tracker), string}
  end

  def put_string_row(tracker, _columns, "\r" <> string) do
    {hard_return(tracker), string}
  end

  def put_string_row(tracker, _columns, "\n" <> string) do
    {hard_return(tracker), string}
  end

  def put_string_row(tracker = %{cursor: cursor}, columns, string = "\e" <> _) do
    case ExTerm.ANSI.parse(string, {tracker.style, cursor}) do
      # no cursor change.
      {rest, {style, ^cursor}} ->
        put_string_row(%{tracker | style: style}, columns, rest)
    end
  end

  def put_string_row(tracker = %{cursor: cursor = {row, column}}, columns, string) do
    case String.next_grapheme(string) do
      nil ->
        tracker

      {grapheme, rest} ->
        updates = [{cursor, %Cell{char: grapheme, style: tracker.style}} | tracker.updates]

        put_string_row(
          %{tracker | cursor: {row, column + 1}, last_updated: cursor, updates: updates},
          columns,
          rest
        )
    end
  end

  @spec send_update(t, keyword) :: t
  def send_update(tracker = %{cursor: cursor, console: console}, opts \\ []) do
    console
    |> Console.put_metadata(:cursor, cursor)
    |> Console.insert(tracker.updates)

    last_updated = if Keyword.get(opts, :with_cursor), do: cursor, else: tracker.last_updated

    case Console.get_metadata(tracker.console, :handle_update) do
      fun when is_function(fun, 1) ->
        fun.(
          Console.update_msg(
            from: tracker.first_updated,
            to: last_updated,
            cursor: cursor,
            last_cell: tracker.last_cell
          )
        )

      nil ->
        :ok

      other ->
        raise "invalid update handler, expected arity 1 fun, got #{inspect(other)}"
    end

    %{tracker | updates: []}
  end

  defp pad_last_row(tracker = %{cursor: {_, cursor_column}}, columns) do
    {row, keys} = Enum.reduce(tracker.updates, {0, MapSet.new()}, fn
      {location = {this_row, _}, _}, {highest_row, keys} ->
        new_highest_row = if this_row > highest_row, do: this_row, else: highest_row
        {new_highest_row, MapSet.put(keys, location)}
    end)

    new_updates = for column <- cursor_column..columns, {row, column} not in keys, reduce: tracker.updates do
      updates -> [{{row, column}, %Cell{}} | updates]
    end

    # fill out the row.
    %{tracker | updates: [{{row, columns + 1}, Cell.sentinel()} | new_updates]}
  end

  # MOVE_SUCCEEDING ROWS.

  # no limit.  Get everything, but don't take the sentinel (default)
  defmatchspec move_rows_ms(row, destination_row, nil) do
    {{^row, column}, cell} when cell.char !== "\n" -> {{destination_row, column}, cell}
  end

  # also grab the sentinel
  defmatchspec move_rows_ms(row, destination_row, :sentinel) do
    {{^row, column}, cell} -> {{destination_row, column}, cell}
  end

  # only grab up to column x
  defmatchspec move_rows_ms(row, destination_row, limit) when is_integer(limit) do
    {{^row, column}, cell} when column <= limit -> {{destination_row, column}, cell}
  end

  @spec move_rows(Console.t(), pos_integer(), pos_integer(), nil | :sentinel | pos_integer()) :: [Console.cell_info]
  defp move_rows(console, row, destination_row, limit \\ nil) do
    Console.select(console, move_rows_ms(row, destination_row, limit))
  end

  # terminate when we are trying to move a row greater than the layout size.
  defp move_succeeding_rows(tracker = %{last_cell: {last_row, _}}, row, _) when row > last_row do
    tracker
  end

  defp move_succeeding_rows(tracker = %{console: console, layout: {_, layout_columns}}, row, move_distance) do
    # get the length of the destination row.
    destination_row = row + move_distance
    source_length = Console.columns(console, row)
    destination_length = Console.columns(console, destination_row)

    new_updates = case source_length do
      length when length === destination_length ->
        # destination size matches the source length.
        console
        |> move_rows(row, destination_row) # obtain the row.
        |> Enum.reverse(tracker.updates)

      length when destination_length === 0 and length === layout_columns ->
        # destination doesn't exist.  Need to make a new row that has a sentinel, but with the same
        # content.
        console
        |> move_rows(row, destination_row, :sentinel)
        |> Enum.reverse(tracker.updates)

      length when length < destination_length ->
        # destination is overfull, we need to pad.
        new_updates = console
        |> move_rows(row, destination_row)
        |> Enum.reverse(tracker.updates)

        Enum.reduce((length + 1)..destination_length, new_updates, fn
          column, so_far -> [{{destination_row, column}, %Cell{}} | so_far]
        end)

      length when destination_length === 0 and length < layout_columns ->
        # destination doesn't exist.   We need to transfer AND pad with a sentinel in
        # the new row.

        new_updates = console
        |> move_rows(row, destination_row)
        |> Enum.reverse(tracker.updates)

        (length + 1)..layout_columns
        |> Enum.reduce(new_updates, fn
          column, so_far -> [{{destination_row, column}, %Cell{}} | so_far]
        end)
        |> List.insert_at(0, {{destination_row, layout_columns + 1}, Cell.sentinel()})

      _ when destination_length === 0->
        # destination doesn't exist.  We need to transfer AND pad with a sentinel

        console
        |> move_rows(row, destination_row, destination_length)
        |> Enum.reverse(tracker.updates)
        |> List.insert_at(0, {{destination_row, layout_columns + 1}, Cell.sentinel()})

      _ ->
        # destination is underfull but exists, only pull up to destination length
        console
        |> move_rows(row, destination_row, destination_length)
        |> Enum.reverse(tracker.updates)
    end

    move_succeeding_rows(%{tracker | updates: new_updates}, row + 1, move_distance)
  end

  defp update_cursor(tracker, old_cursor, insert_row, move_distance) do
    new_cursor = case old_cursor do
      {row, _} when row < insert_row -> old_cursor
      {row, column} ->
        {row + move_distance, column}
    end
    %{tracker | cursor: new_cursor}
  end

  defp update_insert(tracker = %{updates: [{location = {row, column}, _} | _]}) do
    %{tracker | last_updated: location, last_cell: {row, column - 1}}
  end

  # special events that are common

  defp hard_return(tracker = %{cursor: {row, _column}}) do
    new_cursor = {row + 1, 1}

    tracker
    |> Map.put(:cursor, new_cursor)
    |> send_update
    |> Map.merge(%{first_updated: new_cursor, last_updated: new_cursor})
  end

  defp hard_tab(tracker = %{cursor: {row, column}}, columns) do
    new_cursor =
      case (div(column, 10) + 1) * 10 do
        new_column when new_column > columns ->
          {row + 1, 1}

        new_column ->
          {row, new_column}
      end

    tracker
    |> Map.put(:cursor, new_cursor)
    |> send_update
    |> Map.merge(%{first_updated: new_cursor, last_updated: new_cursor})
  end
end
