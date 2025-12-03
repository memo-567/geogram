# Title: Ruins of Azurath

# Player
```
         ___
        |===|
        |___|
  ___  /#####\
 | | |//#####\\
 |(o)|/ ##### \\
 | | |  ^^^^^  &[=======
  \_/   |#|#|
        |_|_|
        [ | ]
```
- Health: 100
- Attack: 15
- Defense: 8
- Experience: 30
- Gold: 50

# Scene: azurath-entrance
> Welcome to the ancient ruins of Azurath. The air is thick with the scent of damp stone and decaying leaves.
> You are a treasure hunter, drawn by the legends of untold riches hidden within.
> The entrance to the ruins is overgrown with vines. Faded carvings on the stone walls hint at the once-great civilization that lived here.

## Choice:
- [Explore the main hall](#scene-main-hall)
- [Investigate the side chamber](#scene-side-chamber)
- [Leave the ruins](#scene-leave-ruins)

# Scene: main-hall
> The main hall is vast, with towering pillars and a high, vaulted ceiling.
> Broken statues and shattered pottery litter the floor.
> As you move deeper into the hall, you notice something glinting in the dim light.
> It appears to be a small, ornate chest partially buried under rubble.

## Random:
- 30% [A skeleton warrior emerges from the shadows!](#scene-fight-skeleton)
- 30% [You find a hidden alcove with a shield](#scene-find-shield)
- 20% [Nothing unusual happens](#scene-continue-hall)
- 20% [You find a pot of coins](#scene-find-coins)

# Scene: fight-skeleton
> A skeleton warrior emerges from the shadows, its hollow eyes glowing with malevolent energy.
> It raises its rusty sword and charges at you!

## Choice:
- [Fight the skeleton!](#opponent-skeleton) -> win:#scene-skeleton-victory; lose:#scene-skeleton-defeat
- [Try to run!](#scene-main-hall)

# Scene: skeleton-victory
> The skeleton crumbles to dust at your feet.
> Among the bones, you find a rusty but usable sword!

## Choice:
- [Take the rusty sword](#item-rusty-sword) -> win:#scene-continue-hall
- [Continue exploring the hall](#scene-continue-hall)

# Scene: skeleton-defeat
> The skeleton's blade finds its mark.
> You stumble backwards, wounded but alive.

## Choice:
- [Retreat to the entrance](#scene-azurath-entrance)

# Scene: find-shield
> As you clear away the rubble, you discover a hidden alcove.
> Inside, you find an ancient shield! It's battered, but it might still offer some protection.

## Choice:
- [Take the ancient shield](#item-ancient-shield) -> win:#scene-continue-hall
- [Leave it and continue](#scene-continue-hall)

# Scene: find-coins
> While exploring the hall, you stumble upon a small pot.
> Inside, you find a stash of coins, glinting in the dim light!

## Choice:
- [Take the coins](#item-coins) -> win:#scene-continue-hall
- [Continue exploring the hall](#scene-continue-hall)

# Scene: continue-hall
> As you move further into the hall, the air grows colder.
> You see a large doorway at the far end, leading deeper into the ruins.
> A chilling presence fills the air...

## Random:
- 50% [A massive figure emerges from the shadows!](#scene-fight-ogre)
- 50% [You find a hidden treasure room!](#scene-hidden-treasure)

# Scene: fight-ogre
> A massive Ogre emerges from the shadows!
> It roars with fury, swinging its massive fists at you!

## Choice:
- [Fight the ogre!](#opponent-ogre) -> win:#scene-ogre-victory; lose:#scene-ogre-defeat
- [Flee back to the entrance!](#scene-azurath-entrance)

# Scene: ogre-victory
> The ogre collapses with a thunderous crash!
> Among its belongings, you find a heavy club and some coins.

## Choice:
- [Take the ogre club](#item-ogre-club) -> win:#scene-hidden-treasure
- [Continue to the treasure room](#scene-hidden-treasure)

# Scene: ogre-defeat
> The ogre's powerful blows are too much!
> You barely escape with your life...

## Choice:
- [Retreat to the entrance](#scene-azurath-entrance)

# Scene: side-chamber
> The side chamber is smaller, with walls covered in intricate carvings.
> A large, menacing statue stands at the far end of the room.
> As you approach the statue, its eyes suddenly glow red!
> The Stone Guardian is awake and ready to defend the chamber!

## Choice:
- [Fight the Stone Guardian!](#opponent-stone-guardian) -> win:#scene-guardian-victory; lose:#scene-guardian-defeat
- [Flee the chamber!](#scene-azurath-entrance)

# Scene: guardian-victory
> The Stone Guardian crumbles to pieces!
> A glowing stone shard falls from where its heart should be.
> Behind the defeated guardian, you see a hidden compartment in the floor!

## Choice:
- [Take the stone shard](#item-stone-shard) -> win:#scene-chamber-treasure
- [Open the hidden compartment](#scene-chamber-treasure)

# Scene: guardian-defeat
> The Stone Guardian's massive fists are too powerful!
> You retreat, battered and bruised.

## Choice:
- [Return to the entrance](#scene-azurath-entrance)

# Scene: chamber-treasure
> Inside the hidden compartment, you find an ancient artifact!
> It's covered in strange runes that seem to shift as you look at them.
> You feel a surge of power as you pick it up.

## Choice:
- [Take the ancient artifact](#item-artifact) -> win:#scene-exit-ruins
- [Leave it and explore elsewhere](#scene-continue-hall)

# Scene: hidden-treasure
> The door creaks open, revealing a room filled with ancient treasures!
> Gold coins, jewels, and artifacts are piled high, glittering in the dim light.
> However, a sense of unease fills the air - this treasure is surely guarded...

## Choice:
- [Take some treasure](#scene-take-treasure)
- [Leave the treasure and exit](#scene-exit-ruins)

# Scene: take-treasure
> As you gather the treasure, you hear a low growl from behind you.
> You turn to see a MASSIVE STONE GOLEM, awakened by your greed!
> Its eyes glow with ancient fury as it raises its enormous fists!

## Choice:
- [Fight the Stone Golem!](#opponent-golem) -> win:#scene-golem-victory; lose:#scene-golem-defeat

# Scene: golem-victory
> The Stone Golem falls with a thunderous crash!
> Among the rubble, you find its magical heart still pulsing with energy.
> You've done it - the treasure of Azurath is yours!

## Choice:
- [Take the golem heart and treasure](#item-golem-heart) -> win:#scene-exit-ruins
- [Exit the ruins victorious!](#scene-exit-ruins)

# Scene: golem-defeat
> The Golem's power is overwhelming!
> You barely escape with your life, leaving the treasure behind...

## Choice:
- [Flee to the entrance](#scene-azurath-entrance)

# Scene: leave-ruins
> Deciding that the ruins are too dangerous, you turn back and leave.
> Perhaps you'll return another day, better prepared.

## Choice:
- [Return to try again](#scene-azurath-entrance)
- [End your adventure](#scene-end)

# Scene: exit-ruins
> You make your way out of the ruins, the sunlight blinding you as you emerge.
> Your pockets are heavier with treasure, and you have stories to tell!

## Choice:
- [Return for another exploration](#scene-azurath-entrance)
- [End your adventure](#scene-end)

# Scene: end
> Your adventure has come to an end.
> Perhaps one day you will return to the ruins of Azurath, but for now, you leave with the stories of what you encountered.
>
> Thank you for playing!
>
> THE END

# Action: attack
> You strike at your opponent with all your might!

```javascript
// Player attacks opponent
var playerAttack = A['Attack'] + (A['Experience'] / 10);
var opponentDef = B['Defense'];
var playerDamage = Math.max(5, Math.floor(playerAttack * 1.5 - opponentDef));
B['Health'] = B['Health'] - playerDamage;

// Check if opponent is defeated
if (B['Health'] <= 0) {
  // Victory! Restore some health
  A['Health'] = Math.min(A['Health'] + 20, 100);
  A['Experience'] = A['Experience'] + 10;
  output = 'win';
} else {
  // Opponent counter-attacks!
  var opponentAttack = B['Attack'];
  var playerDef = A['Defense'];
  var opponentDamage = Math.max(1, Math.floor(opponentAttack - playerDef));
  A['Health'] = A['Health'] - opponentDamage;

  // Check if player is defeated
  if (A['Health'] <= 0) {
    output = 'lose';
  } else {
    output = 'continue';
  }
}
```


# Item: rusty-sword
- Attack: +3
- Description: A worn and damaged sword, but it still has some fight left in it
- Type: weapon

# Item: ancient-shield
- Defense: +5
- Description: A shield from a bygone era, worn but sturdy
- Type: shield

# Item: coins
- Gold: +20
- Description: A stash of ancient coins
- Type: currency

# Item: ogre-club
- Attack: +8
- Description: A massive club wielded by the ogre. Heavy but devastating.
- Type: weapon

# Item: stone-shard
- Attack: +5
- Description: A shard of the Stone Guardian. Surprisingly light with a faint magical aura.
- Type: material

# Item: artifact
- Attack: +8
- Defense: +3
- Description: An ancient artifact covered in shifting runes. Pulses with mysterious power.
- Type: artifact

# Item: golem-heart
- Attack: +10
- Description: The heart of the stone golem, pulsing with immense energy.
- Type: material

# Opponent: skeleton
```
      .-.
     (o o)
      | |
   <--|X|--
      | |
     _| |_
```
- Health: 60
- Attack: 10
- Defense: 5
- Actions: attack, defend
- Description: A skeleton warrior with hollow glowing eyes

# Opponent: ogre
```
                     __/='````'=\_
      ,-,            \ (o)/ (o) \\
     /-_ `'-,         )  (_,    |\\
  / ````==_ /     ,-- \ '==='`  /~~~-,
  \/       /     /     '----`         \
  /       /-.,, /  ,                   `-
 /'--..,_/`-,_ /`-,/                 ,   \
/ `````-/     (    ,,              ,/,    `,
`'--.,_/      /   <,_`'-,-`  `'---`/`      )
             /    |  `-,_`'-,_ .--`      .`
            /.    )------`'-,_`>   ___.-`]
              `--|`````````-- /   /-,_ ``)
                 |           , `-,/`-,_`-
                 \          /\  ,     ',_`>
                  \/`\_/V\_/  \/\,-/\`/
                   ( .__. )    ( ._.  )
                   |      |    |      |
                    \.---_|    |_---,/
                    ooOO(_)    (_)OOoo
```
- Health: 90
- Attack: 14
- Defense: 6
- Actions: attack, defend
- Description: A massive ogre with tremendous strength but slow reflexes

# Opponent: stone-guardian
```
    _____
   /     \
  | O   O |
  |   _   |
  |  ___  |
 /|=======|\
| |       | |
|_|_______|_|
```
- Health: 100
- Attack: 15
- Defense: 10
- Actions: attack, defend
- Description: A massive stone statue animated by ancient magic

# Opponent: golem
```
      ___
     /   \
    | O O |
    |  _  |
   /|=====|\
  | |     | |
  | |_____| |
 /           \
|  |=======|  |
|__|       |__|
```
- Health: 150
- Attack: 20
- Defense: 15
- Actions: attack, defend
- Description: A massive stone golem, awakened by greed, guarding the treasure of Azurath
