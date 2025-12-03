# Title: Dungeon Escape

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
- Attack: 10
- Defense: 5
- Gold: 0

# Scene: start
> You wake up in a dark dungeon cell.
> The iron bars are rusted, and you hear distant footsteps.
> A faint light flickers from a torch down the corridor.

## Choice:
- [Try to bend the bars](#scene-escape-attempt)
- [Wait and observe](#scene-wait)
- [Call out for help](#scene-call-help)

# Scene: escape-attempt
> You strain against the rusty bars with all your might.
> The metal groans but holds firm.
> However, you notice one bar is looser than the others...

## Choice:
- [Keep trying the loose bar](#scene-break-free)
- [Look for another way](#scene-look-around)

# Scene: wait
> You crouch in the shadows and watch.
> A guard walks past, keys jingling at his belt.
> He doesn't notice you're awake.

## Choice:
- [Try to grab the keys](#scene-grab-keys)
- [Let him pass](#scene-guard-gone)

# Scene: call-help
> Your voice echoes through the dungeon.
> Heavy footsteps approach - you've attracted a guard!

## Choice:
- [Fight the guard](#opponent-guard) -> win:#scene-victory; lose:#scene-defeat
- [Pretend to be asleep](#scene-wait)

# Scene: break-free
> With a final heave, the loose bar snaps free!
> You squeeze through the gap into the corridor.
> Freedom is within reach!

## Choice:
- [Sneak towards the exit](#scene-sneak)
- [Search for your belongings](#scene-search)

# Scene: look-around
> You examine your cell more carefully.
> Under the straw bed, you find a rusty shiv!

## Choice:
- [Take the shiv](#item-shiv)
- [Leave it and try the bars again](#scene-break-free)

# Scene: grab-keys
> You reach through the bars as the guard passes.
> He spins around, drawing his sword!

## Choice:
- [Fight!](#opponent-guard) -> win:#scene-victory; lose:#scene-defeat

# Scene: guard-gone
> The guard disappears around a corner.
> Now's your chance to act.

## Choice:
- [Try to bend the bars](#scene-escape-attempt)
- [Look for something useful](#scene-look-around)

# Scene: sneak
> You creep down the torch-lit corridor.
> Suddenly, a massive shadow blocks your path - an OGRE!
> Its beady eyes fix on you as it raises a huge club.

## Choice:
- [Fight the ogre!](#opponent-ogre) -> win:#scene-ogre-victory; lose:#scene-defeat
- [Try to run past it](#scene-final-battle)

# Scene: ogre-victory
> The ogre crashes to the ground, shaking the dungeon walls.
> You step over its massive body and continue to the exit.

## Choice:
- [Continue to freedom](#scene-freedom)

# Scene: search
> You find a storage room with your gear!
> Your sword and armor are here.

## Choice:
- [Take your equipment](#item-sword)
- [Just head for the exit](#scene-sneak)

# Scene: final-battle
> "Halt! Prisoner escaping!"
> A burly guard blocks your path to freedom.

## Choice:
- [Fight for your freedom!](#opponent-dungeon-guard) -> win:#scene-freedom; lose:#scene-defeat

# Scene: victory
> The guard falls to the ground, unconscious.
> You grab his keys and unlock your cell.
> Time to escape!

## Choice:
- [Head for the exit](#scene-sneak)

# Scene: defeat
> The guard overpowers you.
> Everything goes dark...
>
> GAME OVER

# Scene: freedom
> You burst through the door into the cool night air.
> The stars twinkle overhead as you breathe in freedom.
> You've escaped the dungeon!
>
> Congratulations!
>
> THE END

# Action: attack
> You strike at your opponent!

```javascript
var damage = Math.max(1, A['Attack'] - B['Defense']);
B['Health'] = B['Health'] - damage;
if (B['Health'] <= 0) {
  output = 'win';
} else {
  output = 'continue';
}
```

# Action: defend
> You raise your guard!

```javascript
var damage = Math.max(1, Math.floor((B['Attack'] - A['Defense'] * 2) / 2));
A['Health'] = A['Health'] - damage;
if (A['Health'] <= 0) {
  output = 'lose';
} else {
  output = 'continue';
}
```

# Item: shiv
- Attack: +3
- Description: A crude blade fashioned from a broken bar
- Type: weapon

# Item: sword
- Attack: +10
- Defense: +2
- Description: Your trusty sword, finally back in your hands
- Type: weapon

# Opponent: guard
```
      ,O,
     |##|\
    / || \_
   <[==]  |
     /  \
    _|  |_
```
- Health: 30
- Attack: 8
- Defense: 3
- Description: A tired-looking dungeon guard

# Opponent: dungeon-guard
```
      ,O,
     |##|\
    / || \_
   <[==]  |
     /  \
    _|  |_
```
- Health: 50
- Attack: 12
- Defense: 5
- Description: A burly guard in heavy armor

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
- Health: 80
- Attack: 15
- Defense: 3
- Description: A massive green-skinned ogre with a huge club
