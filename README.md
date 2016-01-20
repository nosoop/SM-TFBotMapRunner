# SM-TFBotMapRunner
A SourceMod plugin that restricts the server to run bot-supported maps when the player count is low.

## About
I think TF2 community server owners know the feeling.  Their server is dead all the time, and people aren't joining.  People say that they'd like to join, but "if only there were people on...".  It's an unfortunate catch-22 situation.

To give the server some activity while nobody is around (and waste CPU time while you're at it), you'd use bots.  Unfortunately, maps require navmeshes (navigation meshes) for bots to function.  And they take time to generate.  And maybe some time to fine-tune.  And they don't work for every game mode.

This plugin serves the purpose of allowing the first player to stumble on an unpopulated server to play with bots.  It does this by enforcing the use of maps that have generated navmeshes if the human playing count falls below a specific configurable threshold.

Generated navmeshes are detected if it exists in the mounted filesystems.  Peeking inside BSPs is not supported yet, so you will need to do that manually (see the installation section below).

This plugin requires the functionality of the default Map Chooser plugin to operate.  It can also read the bot quota ConVar from Dr. McKay's [Bot Manager][] plugin for some functionality.

[Bot Manager]: https://forums.alliedmods.net/showthread.php?t=219937

## Installation
1.  Compile and install `tf_bot_map_runner.smx` as you would any other plugin, and copy over the included configuration file.
2.  Modify the configuration file `configs/bot_map_runner.txt` as necessary.  Any maps that should be included regardless of autodetection should be prepended with `+` and a space, any maps that should be excluded should be prepended with a `-` and a space.  Other lines are undetected.  For example:
      ```
      ; Players are stuck in spawn on Helltower
      - plr_hightower_event

      ; Octothorpe has navigation meshes built-in
      + workshop/454721948
      ```
    (The plugin uses `FindMap`, so workshop names should resolve themselves.)

3.  Load the plugin.  The server should log the number of maps available for bots to play on, and will automatically generate a config under `/cfg/sourcemod/plugin.tf_bot_map_runner.cfg`.  The following ConVars are available:
  * `sm_botmap_playercount`:  The player count threshold.  When set to a number `n`, the plugin will only do things if the player count is `n-1`.  If set to `quota`, the plugin will read `tf_bot_quota` (or `sm_bot_quota` if available) to determine the threshold.  (Default: 2 &mdash; plugin will run if fewer than 2 human players are on a playing team)
  * `sm_botmap_duration_fromdisconnect`:  If a player disconnect event puts the server below the threshold on a non bot-supported map, the server will automatically change maps in the specified number of seconds, and players will be notified.  (Default: 90.0 seconds)
  * `sm_botmap_duration_frommapstart`:  Similar to the above, but the player count is checked on map start, just in case the server empties out during the map change for some reason.  (Default: 90.0 seconds)
4.  Generate or download navigation meshes for more maps!  See [this Navigation Mesh thread on Facepunch][nav-thread] for more information.

[nav-thread]: https://www.facepunch.com/threads/1080451

## Known issues
1.  Maps with embedded navigation meshes are not automatically detected.  For now, add it to the `bot_map_runner.txt` configuration.  The plan is to automatically add the current map to a different file under SourceMod's `data/` directory (though how do we detect that the mesh is packed in the file?).
2.  Players are notified of the pending map change whenever they spawn.  I'll have to fix that eventually.
