package golf3d

import "core:fmt"
import sqlite "../../vendor/odin-sqlite3"
import sa "../../vendor/odin-sqlite3/addons"

Shot_Event :: struct {
	tick:       i64,
	player_idx: u8,
	vel:        [3]f32,
}

Replay_DB :: struct {
	db:          ^sqlite.Connection,
	insert_stmt: ^sqlite.Statement,
	is_open:     bool,
}

replay_db: Replay_DB

DB_PATH :: "golf_shots.db"

replay_db_init :: proc(recording: bool) -> bool {
	if replay_db.is_open {
		return true
	}

	mode := recording ? "rw" : "r"
	// If recording and file doesn't exist, sqlite will create it
	result := sqlite.open(cstring(DB_PATH), &replay_db.db)
	if result != .Ok {
		fmt.eprintfln("Failed to open sqlite db: %v", sqlite.errmsg(replay_db.db))
		return false
	}

	// Create table if not exists (safe even when just replaying if db was cleared)
	sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db, `
		CREATE TABLE IF NOT EXISTS shots (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			tick INTEGER NOT NULL,
			player_idx INTEGER NOT NULL,
			vel_x REAL,
			vel_y REAL,
			vel_z REAL
		);
	`))

	sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db, `
		CREATE TABLE IF NOT EXISTS replay_metadata (
			id INTEGER PRIMARY KEY,
			start_tick INTEGER,
			num_players INTEGER
		);
	`))

	if recording {
		// Clear old shots for a fresh recording
		sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db, `DELETE FROM shots;`))
		sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db, `DELETE FROM replay_metadata;`))

		prepare_result := sqlite.prepare_v2(
			replay_db.db,
			"INSERT INTO shots (tick, player_idx, vel_x, vel_y, vel_z) VALUES (?, ?, ?, ?, ?);",
			-1,
			&replay_db.insert_stmt,
			nil,
		)
		if prepare_result != .Ok {
			fmt.eprintfln("Failed to prepare insert stmt: %v", sqlite.errmsg(replay_db.db))
			return false
		}
	}

	replay_db.is_open = true
	return true
}

replay_db_record_shot :: proc(event: Shot_Event) -> bool {
	if !replay_db.is_open || replay_db.insert_stmt == nil {
		return false
	}

	sqlite.reset(replay_db.insert_stmt)
	sqlite.bind_int64(replay_db.insert_stmt, 1, event.tick)
	sqlite.bind_int(replay_db.insert_stmt, 2, cast(i32)event.player_idx)
	sqlite.bind_double(replay_db.insert_stmt, 3, cast(f64)event.vel.x)
	sqlite.bind_double(replay_db.insert_stmt, 4, cast(f64)event.vel.y)
	sqlite.bind_double(replay_db.insert_stmt, 5, cast(f64)event.vel.z)

	result := sqlite.step(replay_db.insert_stmt)
	if result != .Done {
		fmt.eprintfln("Failed to insert shot: %v", sqlite.errmsg(replay_db.db))
		return false
	}
	return true
}

replay_db_load_shots :: proc(allocator := context.allocator) -> []Shot_Event {
	if !replay_db.is_open {
		return nil
	}

	stmt: ^sqlite.Statement
	result := sqlite.prepare_v2(
		replay_db.db,
		"SELECT tick, player_idx, vel_x, vel_y, vel_z FROM shots ORDER BY tick ASC;",
		-1,
		&stmt,
		nil,
	)
	if result != .Ok {
		fmt.eprintfln("Failed to prepare select: %v", sqlite.errmsg(replay_db.db))
		return nil
	}
	defer sqlite.finalize(stmt)

	events := make([dynamic]Shot_Event, allocator)
	for {
		result = sqlite.step(stmt)
		if result != .Row {
			break
		}
		append(&events, Shot_Event{
			tick       = sqlite.column_int64(stmt, 0),
			player_idx = cast(u8)sqlite.column_int(stmt, 1),
			vel = {
				cast(f32)sqlite.column_double(stmt, 2),
				cast(f32)sqlite.column_double(stmt, 3),
				cast(f32)sqlite.column_double(stmt, 4),
			},
		})
	}

	return events[:]
}

replay_db_save_metadata :: proc(start_tick: i64, num_players: int) -> bool {
	if !replay_db.is_open {
		return false
	}
	sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db, `DELETE FROM replay_metadata;`))
	sa.on_fail_panic(replay_db.db, sa.execute(replay_db.db,
		"INSERT INTO replay_metadata (id, start_tick, num_players) VALUES (1, ?, ?);",
		{
			{1, start_tick},
			{2, cast(i32)num_players},
		},
	))
	return true
}

replay_db_close :: proc() {
	if replay_db.insert_stmt != nil {
		sqlite.finalize(replay_db.insert_stmt)
		replay_db.insert_stmt = nil
	}
	if replay_db.db != nil {
		sqlite.close(replay_db.db)
		replay_db.db = nil
	}
	replay_db.is_open = false
}
