# Sons de Mikky

Mikky joue les fichiers `.mp3` de ce dossier (`app/lib/sound/sound_board.dart` dit lequel pour quoi). Un fichier absent : Mikky reste silencieux, rien ne casse. Le lecteur ne lit que le `.mp3` : convertir les autres formats (`ffmpeg -i son.ogg -codec:a libmp3lame -q:a 2 son.mp3`).

**Les fichiers ne sont pas dans git** : le dépôt est public, et ces sons ne sont pas à nous. Les garder en local, ou les remplacer par des sons libres (CC0) ou faits pour Mikky avant toute distribution.

Depuis le 2026-10-05 : les sons de `app/assets/sounds_test/sounds` (les `.ogg` convertis ; quand un son existait dans les deux formats, l'`.ogg` est devenu `<nom>_2.mp3`). Les anciens sons PSP sont gardés dans `app/assets/sounds_test/psp`.

Utilisés aujourd'hui : `back`, `folder_close`, `folder_open`, `launch`, `navigate`, `retroachievements`, `select`. Les autres attendent leur place, à choisir avec l'utilisateur son par son : `discord_close`, `discord_open`, `error`, `grid_zoom_in` (et `_2`), `grid_zoom_out`, `notification`, `open_edit`, `pop`, `reorder_pickup`, `reorder_place`, `saving`, `screen_swap`, `select_2`, `slider_decrease`, `slider_increase`.
