#ifndef RUNNER_SOUND_H_
#define RUNNER_SOUND_H_

#include <windows.h>
#include <xaudio2.h>

#include <map>
#include <set>
#include <string>
#include <vector>

// Mikky's sounds: short files in `data/flutter_assets/assets/sounds/` next
// to the executable. Each one is decoded once by Media Foundation (any
// format Windows reads, MP3 included) into memory, then played by
// XAudio2: on time, several at once, each at its own volume. The audio
// engine stops as soon as nothing plays (Reap), so nothing runs between
// two sounds. A missing or unreadable file stays silent: the sounds are
// not in git (see app/assets/sounds/README.md).
class SoundPlayer {
 public:
  SoundPlayer() = default;
  ~SoundPlayer();

  // Decodes these sounds now, so the first play is not late.
  void Preload(const std::set<std::string>& names);

  // Plays sound |name| (letters, digits and '_' only) at |volume| 0..1.
  // Returns how long it lasts in milliseconds, 0 if nothing plays.
  int Play(const std::string& name, double volume);

  // Frees the sounds that ended; stops the engine when none is left.
  // Returns true while some still play.
  bool Reap();

 private:
  struct Clip {
    std::vector<BYTE> format;  // WAVEFORMATEX (or EXTENSIBLE)
    std::vector<BYTE> pcm;
    int duration_ms = 0;
  };

  bool Start();
  const Clip* Load(const std::string& name);
  std::wstring Directory();

  bool started_ = false;
  bool failed_ = false;
  bool engine_running_ = false;
  IXAudio2* audio_ = nullptr;
  IXAudio2MasteringVoice* master_ = nullptr;
  std::vector<IXAudio2SourceVoice*> voices_;
  std::map<std::string, Clip> clips_;
  std::set<std::string> missing_;
  std::wstring directory_;
};

#endif  // RUNNER_SOUND_H_
