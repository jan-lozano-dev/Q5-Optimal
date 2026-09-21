# PROP — Java OOP 01

## Goal

Construir un mini sistema de joc orientat a objectes sense copiar sintaxi.

## Requirements

Implementa:

- `Player` amb `name`, `score` i encapsulació correcta.
- `HumanPlayer extends Player`.
- `BotPlayer extends Player` amb un camp `difficulty`.
- Una interface `Playable` amb un mètode `playTurn()`.
- Override de `playTurn()` en les subclasses.
- Un `ArrayList<Player>` amb diversos jugadors.
- Un `HashMap<String, Player>` per indexar-los per nom.
- Ordenació dels jugadors per puntuació amb `Comparator`.

## Constraints

Primera passada:

- Sense ChatGPT.
- Sense copiar codi.
- Intenta no consultar documentació durant els primers 15 minuts.
- Compila i corregeix a partir dels errors del compilador.

## Retrieval questions

Quan acabis, respon sense apunts:

1. Quina diferència hi ha entre `extends` i `implements`?
2. Què fa `@Override`?
3. Quan utilitzaries `super(...)`?
4. Diferència entre `==` i `.equals()` amb objectes.
5. Java passa objectes per referència o passa el valor d'una referència?
6. Per què `ArrayList<int>` no és vàlid?
7. Diferència conceptual entre `static` i un membre d'instància.
8. Què implica `final` en variable, mètode i classe?

## Mastery Gate

No el consideris dominat fins que puguis crear una versió equivalent des de zero en una sessió posterior, sense mirar aquesta implementació.
