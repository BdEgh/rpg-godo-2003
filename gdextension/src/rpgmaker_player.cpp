#include "rpgmaker_player.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include "baseui.h"
#include "filefinder.h"
#include "game_clock.h"
#include "graphics.h"
#include "instrumentation.h"
#include "input.h"
#include "message_overlay.h"
#include "player.h"
#include "scene.h"
#include "output.h"
#include "scene_debug.h"
#include "scene_load.h"
#include "scene_save.h"
#include "transition.h"

#include "multiplayer/game_multiplayer.h"

#include "platform/godot/ui.h"

#include <cstring>
#include <stdexcept>
#include <vector>
#include <string>

namespace godot {

RPGMakerPlayer::RPGMakerPlayer() {}

RPGMakerPlayer::~RPGMakerPlayer() {
	stop_game();
}

void RPGMakerPlayer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_game_path", "path"), &RPGMakerPlayer::set_game_path);
	ClassDB::bind_method(D_METHOD("get_game_path"), &RPGMakerPlayer::get_game_path);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "game_path", PROPERTY_HINT_DIR), "set_game_path", "get_game_path");

	ClassDB::bind_method(D_METHOD("start_game"), &RPGMakerPlayer::start_game);
	ClassDB::bind_method(D_METHOD("stop_game"), &RPGMakerPlayer::stop_game);
	ClassDB::bind_method(D_METHOD("open_save_menu"), &RPGMakerPlayer::open_save_menu);
	ClassDB::bind_method(D_METHOD("open_load_menu"), &RPGMakerPlayer::open_load_menu);
	ClassDB::bind_method(D_METHOD("open_debug_menu"), &RPGMakerPlayer::open_debug_menu);
	ClassDB::bind_method(D_METHOD("get_frame_texture"), &RPGMakerPlayer::get_frame_texture);
	ClassDB::bind_method(D_METHOD("is_running"), &RPGMakerPlayer::is_running);
	ClassDB::bind_method(D_METHOD("is_map_ready"), &RPGMakerPlayer::is_map_ready);
	ClassDB::bind_method(D_METHOD("mp_set_session_active", "active"), &RPGMakerPlayer::mp_set_session_active);
	ClassDB::bind_method(D_METHOD("mp_notify_room_ready"), &RPGMakerPlayer::mp_notify_room_ready);
	ClassDB::bind_method(D_METHOD("inject_key", "easyrpg_key_id", "pressed"), &RPGMakerPlayer::inject_key);

	ClassDB::bind_method(
		D_METHOD("mp_add_player", "id", "x", "y", "sprite_name", "sprite_index", "facing", "speed"),
		&RPGMakerPlayer::mp_add_player
	);
	ClassDB::bind_method(D_METHOD("mp_remove_player", "id"), &RPGMakerPlayer::mp_remove_player);
	ClassDB::bind_method(D_METHOD("mp_move_player", "id", "x", "y"), &RPGMakerPlayer::mp_move_player);
	ClassDB::bind_method(D_METHOD("mp_set_player_facing", "id", "facing"), &RPGMakerPlayer::mp_set_player_facing);
	ClassDB::bind_method(D_METHOD("mp_set_player_speed", "id", "speed"), &RPGMakerPlayer::mp_set_player_speed);
	ClassDB::bind_method(D_METHOD("mp_set_player_sprite", "id", "name", "index"), &RPGMakerPlayer::mp_set_player_sprite);
	ClassDB::bind_method(D_METHOD("mp_set_player_transparency", "id", "transparency"), &RPGMakerPlayer::mp_set_player_transparency);
	ClassDB::bind_method(D_METHOD("mp_set_player_hidden", "id", "hidden"), &RPGMakerPlayer::mp_set_player_hidden);
	ClassDB::bind_method(D_METHOD("mp_flash_player", "id", "r", "g", "b", "power", "frames"), &RPGMakerPlayer::mp_flash_player);
	ClassDB::bind_method(D_METHOD("mp_sync_local_player"), &RPGMakerPlayer::mp_sync_local_player);
	ClassDB::bind_method(D_METHOD("mp_set_room", "room_id"), &RPGMakerPlayer::mp_set_room);
	ClassDB::bind_method(D_METHOD("mp_set_room_id", "room_id"), &RPGMakerPlayer::mp_set_room_id);
	ClassDB::bind_method( D_METHOD("mp_play_se", "name", "volume", "tempo", "balance"), &RPGMakerPlayer::mp_play_se);
	ClassDB::bind_method(D_METHOD("mp_set_player_name", "id", "name"), &RPGMakerPlayer::mp_set_player_name);
	ClassDB::bind_method(D_METHOD("mp_set_player_system_graphic", "id", "sys_name"), &RPGMakerPlayer::mp_set_player_system_graphic);
	ClassDB::bind_method(D_METHOD("mp_set_nametag_mode", "mode"), &RPGMakerPlayer::mp_set_nametag_mode);

	ClassDB::bind_method(D_METHOD("set_resolution", "width", "height"), &RPGMakerPlayer::set_resolution);
	ClassDB::bind_method(D_METHOD("get_screen_width"), &RPGMakerPlayer::get_screen_width);
	ClassDB::bind_method(D_METHOD("get_screen_height"), &RPGMakerPlayer::get_screen_height);

	ClassDB::bind_method(D_METHOD("audio_pull_frames", "frame_count"), &RPGMakerPlayer::audio_pull_frames);
	ClassDB::bind_method(D_METHOD("get_audio_sample_rate"), &RPGMakerPlayer::get_audio_sample_rate);

	ADD_SIGNAL(
		MethodInfo("resolution_changed",
			PropertyInfo(Variant::INT, "width"),
			PropertyInfo(Variant::INT, "height")
		)
	);

	ADD_SIGNAL(
		MethodInfo("player_moved",
			PropertyInfo(Variant::INT, "x"),
			PropertyInfo(Variant::INT, "y")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_facing_changed",
			PropertyInfo(Variant::INT, "dir")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_speed_changed",
			PropertyInfo(Variant::INT, "speed")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_sprite_changed",
			PropertyInfo(Variant::STRING, "name"), PropertyInfo(Variant::INT, "index")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_jumped",
			PropertyInfo(Variant::INT, "x"), PropertyInfo(Variant::INT, "y")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_flashed",
			PropertyInfo(Variant::INT, "r"), PropertyInfo(Variant::INT, "g"),
			PropertyInfo(Variant::INT, "b"), PropertyInfo(Variant::INT, "power"),
			PropertyInfo(Variant::INT, "frames")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_transparency_changed",
			PropertyInfo(Variant::INT, "transparency")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_hidden_changed",
			PropertyInfo(Variant::BOOL, "hidden")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_teleported",
			PropertyInfo(Variant::INT, "map_id"),
			PropertyInfo(Variant::INT, "x"), PropertyInfo(Variant::INT, "y")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_se_played",
			PropertyInfo(Variant::STRING, "name"), PropertyInfo(Variant::INT, "volume"),
			PropertyInfo(Variant::INT, "tempo"),  PropertyInfo(Variant::INT, "balance")
		)
	);
	ADD_SIGNAL(
		MethodInfo("player_system_changed",
			PropertyInfo(Variant::STRING, "sys_name")
		)
	);
	ADD_SIGNAL(
		MethodInfo("map_changed",
			PropertyInfo(Variant::INT, "map_id")
		)
	);
	ADD_SIGNAL(
		MethodInfo("switch_set",
			PropertyInfo(Variant::INT, "switch_id"), PropertyInfo(Variant::INT, "value")
		)
	);
	ADD_SIGNAL(
		MethodInfo("variable_set",
			PropertyInfo(Variant::INT, "var_id"), PropertyInfo(Variant::INT, "value")
		)
	);
	ADD_SIGNAL(
		MethodInfo("event_triggered",
			PropertyInfo(Variant::INT, "event_id"), PropertyInfo(Variant::BOOL, "action")
		)
	);
}

void RPGMakerPlayer::_ready() {
	frame_texture_ = ImageTexture::create_from_image(
		Image::create(320, 240, false, Image::FORMAT_RGBA8));
}

void RPGMakerPlayer::_process(double) {
	if (!engine_running_) return;
	assert(Scene::instance);

	try {
		const auto frame_time = Game_Clock::now();
		Game_Clock::OnNextFrame(frame_time);

		Player::UpdateInput();

		if (!DisplayUi->ProcessEvents()) {
			Scene::PopUntil(Scene::Null);
			stop_game();
			return;
		}

		int num_updates = 0;
		while (Game_Clock::NextGameTimeStep()) {
			if (num_updates > 0) {
				Player::UpdateInput();
				if (!DisplayUi->ProcessEvents()) {
					Scene::PopUntil(Scene::Null);
					stop_game();
					return;
				}
			}
			Scene::old_instances.clear();
			Scene::instance->MainFunction();

			Graphics::GetMessageOverlay().Update();

			++num_updates;
		}

		if (num_updates == 0) {
			Input::UpdateSystem();
		}

		Player::Draw();
		Scene::old_instances.clear();

		if (Player::exit_flag ||
			(!Transition::instance().IsActive() && Scene::instance->type == Scene::Null)) {
			stop_game();
		}
	} catch (const std::exception& e) {
		UtilityFunctions::push_error(
			String("RPGMakerPlayer: engine error in _process: ") + String(e.what()));
		engine_running_ = false;
		godot_ui_ = nullptr;
		DisplayUi.reset();
	} catch (...) {
		UtilityFunctions::push_error("RPGMakerPlayer: unknown engine error in _process().");
		engine_running_ = false;
		godot_ui_ = nullptr;
		DisplayUi.reset();
	}
}

void RPGMakerPlayer::_notification(int p_what) {
	if (p_what == NOTIFICATION_EXIT_TREE) {
		stop_game();
	}
}

void RPGMakerPlayer::set_game_path(const String& path) { game_path_ = path; }
String RPGMakerPlayer::get_game_path() const { return game_path_; }

void RPGMakerPlayer::start_game() {
	if (engine_running_) {
		UtilityFunctions::push_warning("RPGMakerPlayer: start_game() called while already running.");
		return;
	}
	if (game_path_.is_empty()) {
		UtilityFunctions::push_error("RPGMakerPlayer: game_path is not set.");
		return;
	}

	try {
		String abs_path = ProjectSettings::get_singleton()->globalize_path(game_path_);
		std::string path_str = abs_path.utf8().get_data();
		UtilityFunctions::print("RPGMakerPlayer: starting game at: ", abs_path);

		std::vector<std::string> args = { "easyrpg-player" };
		Player::Init(args);

		auto gamefs = FileFinder::Root().Create(FileFinder::MakeCanonical(path_str, 0));
		if (!gamefs) {
			throw std::runtime_error("Cannot create filesystem for path: " + path_str);
		}
		FileFinder::SetGameFilesystem(gamefs);
		Output::Debug("RPGMakerPlayer: game filesystem set to: {}", path_str);

		FileExtGuesser::RPG2KNonStandardFilenameGuesser rpg2kRemap;
		if (!FileFinder::IsRPG2kProject(FileFinder::Game()) &&
			!FileFinder::IsEasyRpgProject(FileFinder::Game())) {

			rpg2kRemap = FileExtGuesser::GetRPG2kProjectWithRenames(FileFinder::Game());
			if (rpg2kRemap.Empty()) {
				UtilityFunctions::push_error("RPGMakerPlayer: game_path does not appear to be a valid RPG Maker 2000/2003 project.");
				Player::Exit();
				return;
			}
		}

		godot_ui_ = dynamic_cast<GodotUi*>(DisplayUi.get());
		if (!godot_ui_) {
			UtilityFunctions::push_error(
				"RPGMakerPlayer: DisplayUi is not a GodotUi instance. "
				"Make sure PLAYER_TARGET_PLATFORM=godot is set at compile time.");
			Player::Exit();
			return;
		}

		godot_ui_->SetFrameCallback(
			[this](const uint8_t* pixels, int w, int h, int pitch) {
				on_frame_ready(pixels, w, h, pitch);
			}
		);

		Player::CreateGameObjects();
		Instrumentation::Init("EasyRPG-Player");
		Scene::PushTitleScene(false);
		Player::reset_flag = false;

		auto& cbs = GMI().mp_callbacks;

		cbs.on_moved = [this](int x, int y) {
			emit_signal("player_moved", x, y);
		};
		cbs.on_facing = [this](int dir) {
			emit_signal("player_facing_changed", dir);
		};
		cbs.on_speed = [this](int spd) {
			emit_signal("player_speed_changed", spd);
		};
		cbs.on_sprite = [this](const std::string& name, int idx) {
			emit_signal("player_sprite_changed", String(name.c_str()), idx);
		};
		cbs.on_jumped = [this](int x, int y) {
			emit_signal("player_jumped", x, y);
		};
		cbs.on_flash = [this](int r, int g, int b, int p, int f) {
			emit_signal("player_flashed", r, g, b, p, f);
		};
		cbs.on_transparency = [this](int t) {
			emit_signal("player_transparency_changed", t);
		};
		cbs.on_hidden = [this](bool hidden) {
			emit_signal("player_hidden_changed", hidden);
		};
		cbs.on_teleported = [this](int map_id, int x, int y) {
			emit_signal("player_teleported", map_id, x, y);
		};
		cbs.on_se = [this](const std::string& n, int vol, int tempo, int bal) {
			emit_signal("player_se_played", String(n.c_str()), vol, tempo, bal);
		};
		cbs.on_system = [this](const std::string& sys) {
			emit_signal("player_system_changed", String(sys.c_str()));
		};
		cbs.on_map_changed = [this](int map_id) {
			emit_signal("map_changed", map_id);
		};
		cbs.on_switch_set = [this](int sw_id, int val) {
			emit_signal("switch_set", sw_id, val);
		};
		cbs.on_variable_set = [this](int var_id, int val) {
			emit_signal("variable_set", var_id, val);
		};
		cbs.on_event_triggered = [this](int ev_id, bool action) {
			emit_signal("event_triggered", ev_id, action);
		};

		engine_running_ = true;
		UtilityFunctions::print("RPGMakerPlayer: engine started successfully.");

	} catch (const std::exception& e) {
		UtilityFunctions::push_error(
			String("RPGMakerPlayer: engine error: ") + String(e.what()));
		engine_running_ = false;
		godot_ui_ = nullptr;
		Player::Exit();
		DisplayUi.reset();
	} catch (...) {
		UtilityFunctions::push_error("RPGMakerPlayer: unknown engine error during start_game().");
		engine_running_ = false;
		godot_ui_ = nullptr;
		Player::Exit();
		DisplayUi.reset();
	}
}

void RPGMakerPlayer::stop_game() {
	if (!engine_running_) return;
	engine_running_ = false;
	godot_ui_ = nullptr;
	Player::Exit();
}

Ref<ImageTexture> RPGMakerPlayer::get_frame_texture() const { return frame_texture_; }
bool RPGMakerPlayer::is_running() const { return engine_running_; }

PackedFloat32Array RPGMakerPlayer::audio_pull_frames(int frame_count) {
	PackedFloat32Array result;
#if SUPPORT_AUDIO
	if (!godot_ui_ || frame_count <= 0) return result;

	auto s16 = godot_ui_->PullAudioFrames(frame_count);
	const int total = static_cast<int>(s16.size());
	result.resize(total);
	float* dst = result.ptrw();
	constexpr float inv = 1.0f / 32768.0f;
	for (int i = 0; i < total; ++i) {
		dst[i] = static_cast<float>(s16[i]) * inv;
	}
#endif
	return result;
}

int RPGMakerPlayer::get_audio_sample_rate() const {
#if SUPPORT_AUDIO
	if (godot_ui_) return godot_ui_->GetAudioSampleRate();
#endif
	return 44100;
}

bool RPGMakerPlayer::is_map_ready() const {
	if (!engine_running_) return false;
	return Scene::Find(Scene::SceneType::Map) != nullptr;
}

void RPGMakerPlayer::mp_set_session_active(bool active) {
	if (!engine_running_) return;
	GMI().session_active = active;
}

void RPGMakerPlayer::mp_notify_room_ready() {
	if (!engine_running_) return;
	GMI().switching_room = false;
}

void RPGMakerPlayer::inject_key(int easyrpg_key_id, bool pressed) {
	if (godot_ui_)
		godot_ui_->SetKeyState(easyrpg_key_id, pressed);
}

void RPGMakerPlayer::open_save_menu() {
	if (!engine_running_ || !Scene::instance) return;
	Scene::instance->SetRequestedScene(std::make_shared<Scene_Save>());
}

void RPGMakerPlayer::open_load_menu() {
	if (!engine_running_ || !Scene::instance) return;
	Scene::instance->SetRequestedScene(std::make_shared<Scene_Load>());
}

void RPGMakerPlayer::open_debug_menu() {
	if (!engine_running_ || !Scene::instance) return;
	Scene::instance->SetRequestedScene(std::make_shared<Scene_Debug>());
}

bool RPGMakerPlayer::set_resolution(int width, int height) {
	if (!engine_running_) {
		UtilityFunctions::push_warning(
			"RPGMakerPlayer: set_resolution() called while engine is not running.");
		return false;
	}
	if (width <= 0 || height <= 0) {
		UtilityFunctions::push_error(
			"RPGMakerPlayer: set_resolution() called with invalid dimensions.");
		return false;
	}
	bool ok = Player::ChangeResolution(width, height);
	if (!ok) {
		UtilityFunctions::push_warning(
			String("RPGMakerPlayer: resolution change to ") +
			String::num_int64(width) + "x" + String::num_int64(height) + " failed.");
	}
	return ok;
}

int RPGMakerPlayer::get_screen_width() const {
	return Player::screen_width;
}

int RPGMakerPlayer::get_screen_height() const {
	return Player::screen_height;
}

void RPGMakerPlayer::mp_add_player(int id, int x, int y,
                                   const String& sprite_name, int sprite_index,
                                   int facing, int speed) {
	if (!engine_running_) return;
	GMI().GodotMpAddPlayer(id, x, y, sprite_name.utf8().get_data(), sprite_index, facing, speed);
}

void RPGMakerPlayer::mp_remove_player(int id) {
	if (!engine_running_) return;
	GMI().GodotMpRemovePlayer(id);
}

void RPGMakerPlayer::mp_move_player(int id, int x, int y) {
	if (!engine_running_) return;
	GMI().GodotMpMovePlayer(id, x, y);
}

void RPGMakerPlayer::mp_set_player_facing(int id, int facing) {
	if (!engine_running_) return;
	GMI().GodotMpSetFacing(id, facing);
}

void RPGMakerPlayer::mp_set_player_speed(int id, int speed) {
	if (!engine_running_) return;
	GMI().GodotMpSetSpeed(id, speed);
}

void RPGMakerPlayer::mp_set_player_sprite(int id, const String& name, int index) {
	if (!engine_running_) return;
	GMI().GodotMpSetSprite(id, name.utf8().get_data(), index);
}

void RPGMakerPlayer::mp_set_player_transparency(int id, int transparency) {
	if (!engine_running_) return;
	GMI().GodotMpSetTransparency(id, transparency);
}

void RPGMakerPlayer::mp_set_player_hidden(int id, bool hidden) {
	if (!engine_running_) return;
	GMI().GodotMpSetHidden(id, hidden);
}

void RPGMakerPlayer::mp_flash_player(int id, int r, int g, int b, int power, int frames) {
	if (!engine_running_) return;
	GMI().GodotMpFlash(id, r, g, b, power, frames);
}

void RPGMakerPlayer::mp_sync_local_player() {
	if (!engine_running_) return;
	GMI().GodotFireLocalPlayerCallbacks();
}

void RPGMakerPlayer::mp_set_room(int room_id) {
	if (!engine_running_) return;
	GMI().Connect(room_id, true);
}

void RPGMakerPlayer::mp_set_room_id(int room_id) {
	if (!engine_running_) return;
	GMI().room_id = room_id;
}

void RPGMakerPlayer::mp_play_se(const String& name, int volume, int tempo, int balance) {
	if (!engine_running_) return;
	GMI().GodotMpPlaySe(name.utf8().get_data(), volume, tempo, balance);
}

void RPGMakerPlayer::mp_set_player_name(int id, const String& name) {
	if (!engine_running_) return;
	GMI().GodotMpSetPlayerName(id, name.utf8().get_data());
}

void RPGMakerPlayer::mp_set_player_system_graphic(int id, const String& sys_name) {
	if (!engine_running_) return;
	GMI().GodotMpSetPlayerSystemGraphic(id, sys_name.utf8().get_data());
}

void RPGMakerPlayer::mp_set_nametag_mode(int mode) {
	if (!engine_running_) return;
	GMI().SetNametagMode(mode);
}

void RPGMakerPlayer::on_frame_ready(const uint8_t* pixels, int width, int height, int pitch) {
	if (!pixels || width <= 0 || height <= 0) return;

	const bool size_changed = frame_image_.is_null() ||
		frame_image_->get_width()  != width ||
		frame_image_->get_height() != height;

	if (size_changed) {
		frame_image_ = Image::create(width, height, false, Image::FORMAT_RGBA8);
	}

	// ynoengine ARGB8888 (LE: B G R A)
	// Godot RGBA8888 (R G B A)
	PackedByteArray data;
	data.resize(width * height * 4);
	uint8_t* dst = data.ptrw();

	for (int y = 0; y < height; ++y) {
		const uint8_t* src_row = pixels + y * pitch;
		uint8_t* dst_row = dst + y * width * 4;
		for (int x = 0; x < width; ++x) {
			uint8_t b = src_row[x * 4 + 0];
			uint8_t g = src_row[x * 4 + 1];
			uint8_t r = src_row[x * 4 + 2];
			dst_row[x * 4 + 0] = r;
			dst_row[x * 4 + 1] = g;
			dst_row[x * 4 + 2] = b;
			dst_row[x * 4 + 3] = 255;
		}
	}

	frame_image_->set_data(width, height, false, Image::FORMAT_RGBA8, data);

	if (frame_texture_.is_null() || size_changed) {
		frame_texture_ = ImageTexture::create_from_image(frame_image_);
		emit_signal("resolution_changed", width, height);
	} else {
		frame_texture_->update(frame_image_);
	}
}

} // namespace godot
