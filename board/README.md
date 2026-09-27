# Board

Three columns, three folders. Move the file, that is the whole workflow.

    board/not-done/     backlog
    board/in-progress/  actively being built, keep this to 1 or 2
    board/done/         shipped and verified

Move a card:

    mv board/not-done/F04-*.md board/in-progress/

Card ids are stable. `F01` stays `F01` wherever it lives, so `CONTEXT.md`
and commit messages can reference it.

A card only moves to `done/` when its Acceptance block is actually
verified by running something, not by the code merely compiling.
