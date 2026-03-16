## What does this PR do?

<!-- Brief description -->

## Checklist

- [ ] All 8 patches pass against the latest Claude Code release
- [ ] Patcher is idempotent (second run shows all SKIP)
- [ ] Shell scripts pass `bash -n` syntax check
- [ ] Python patcher passes `python3 -c "compile(open('patch.py').read(), 'patch.py', 'exec')"`
- [ ] No external dependencies added
