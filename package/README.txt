Black 2 MMO - play Pokemon Black 2 online with your friends, all in the same Unova.

You need:
  - BizHawk 2.9 or newer (Windows): https://github.com/TASEmulators/BizHawk/releases
  - Your own Pokemon Black 2 (USA) ROM. Nothing from the game is included here.
  - One person in the group hosts the server: that needs Node.js 18+ (https://nodejs.org).

Setup:
  1. Double-click "Install Black 2 MMO.bat". It asks for your name, the server address,
     a room code, where BizHawk is and where your ROM is.
  2. Double-click "Play Black 2 MMO.bat".

Hosting: double-click "Start server.bat". It prints the address the others type in.
Over the internet, Tailscale (https://tailscale.com) on everyone's PC is the easiest way;
or forward TCP port 7777 on the host's router.

In game:
  - Friends on your map show up as trainers (Nate or Rosa) with their
    name above them. They walk, run and turn as they do in their game.
  - Walk up to a friend and press A: you see their greeting, and they see you're talking.
  - Hold Tab for the list of who's online and where.
  - The "Black 2 MMO" window: chat (type /who to list players), trading, and
    "Battle their team" (the game's AI plays your friend's Pokemon; your party, EXP and
    money are put back afterwards, win or lose).
  - Friends get a notice when you catch a Pokemon, one evolves or you earn a badge.

Back up your save before playing. Settings live in lua\b2mmo.ini. To change anything,
including where BizHawk or your ROM is, run "Install Black 2 MMO.bat" again: it
remembers your answers, so just press Enter on the ones you keep.
