# Probe agent

A one-shot process that stands in for a harness. It writes a file, tries a write that policy should reject, then asks `curl` for one allowed host and one denied host.

Build and run it through the lab scripts:

```bash
make demo
```

The image is Alpine plus Python 3 and curl. It has no model client and no API key. [docs/05-models.md](../../docs/05-models.md) is the path that attaches a model later, using this same image's `curl`.
