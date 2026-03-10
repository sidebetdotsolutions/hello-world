# SOPS + age: Secret Management for Your Linux Fleet

## 1. Install on every machine

```bash
# age (encryption tool)
sudo dnf install -y age

# sops (encrypted file manager)
# Check https://github.com/getsops/sops/releases for latest version
SOPS_VERSION=3.9.4
curl -LO "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
sudo install sops-v${SOPS_VERSION}.linux.amd64 /usr/local/bin/sops
rm sops-v${SOPS_VERSION}.linux.amd64
```

Verify:

```bash
age --version
sops --version
```

## 2. Generate a key on each machine

Run this on **every** machine that needs to decrypt secrets:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

This prints a public key like:

```
age1abc123...
```

**Save every machine's public key somewhere** (a text file, a wiki, whatever). You'll
need them all in the next step. The private key stays on that machine only.

> **Tip:** Name your keys by hostname so you can track them:
> ```
> # webserver-01:  age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
> # api-server-02: age1yr53hey9fw0sql6g3pz4ml39gxpvw5mmekzn2mqn3hqvwtfxuassq0wzae
> # dev-laptop:    age1zetamrjmz5cvrk04z53jk02e7n540m4tsfxwu57s3jrkltxweyuqq8fdxe
> ```

## 3. Set up the repo

```bash
cd ~/empire/hello-world
```

Create `.sops.yaml` at the repo root. This tells sops which keys can decrypt which
files:

```yaml
# .sops.yaml
creation_rules:
  # Secrets shared across all machines
  - path_regex: secrets/shared\.env$
    age: >-
      age1ql3z7hjy...,
      age1yr53hey9f...,
      age1zetamrjmz...

  # Production-only secrets (only prod machines' keys listed)
  - path_regex: secrets/prod\.env$
    age: >-
      age1ql3z7hjy...,
      age1yr53hey9f...

  # Dev-only secrets
  - path_regex: secrets/dev\.env$
    age: >-
      age1zetamrjmz...
```

Replace the `age1...` values with your actual machine public keys (comma-separated).

## 4. Create your first encrypted secret file

```bash
mkdir -p secrets

# Create and encrypt in one step — this opens your $EDITOR
sops secrets/shared.env
```

In the editor, write your secrets in dotenv format:

```
OPENAI_API_KEY=sk-abc123...
DATABASE_URL=postgres://user:pass@host:5432/db
STRIPE_SECRET=sk_live_...
```

Save and quit. The file on disk is now encrypted. If you `cat` it, you'll see
age-encrypted ciphertext — not your plaintext secrets.

### Alternative: encrypt an existing file

```bash
# If you already have a plaintext .env file
sops --encrypt --in-place secrets/shared.env
```

## 5. Commit the encrypted files

```bash
# The encrypted files are safe to commit
git add .sops.yaml secrets/
git commit -m "Add encrypted secrets"
git push
```

**Important:** Add a safety net so you never commit plaintext:

```bash
# .gitignore — ignore any decrypted output files
*.decrypted
*.decrypted.*
.env
.env.local
```

## 6. Use secrets on each machine

### Option A: Decrypt to a temporary file

```bash
cd ~/empire/hello-world
git pull

# Decrypt to a temp file, use it, then clean up
sops -d secrets/shared.env > /tmp/.env
source /tmp/.env
rm /tmp/.env

# Now your env vars are set for this shell session
echo $OPENAI_API_KEY
```

### Option B: Inline with a command (no file on disk)

```bash
# Run a command with decrypted env vars injected
sops exec-env secrets/shared.env 'python app.py'

# Or start a subshell with the secrets loaded
sops exec-env secrets/shared.env 'bash'
```

### Option C: Systemd service integration

Create a wrapper script `/usr/local/bin/start-myapp.sh`:

```bash
#!/bin/bash
cd /home/deploy/empire/hello-world
exec sops exec-env secrets/shared.env 'python app.py'
```

Then reference it in your systemd unit:

```ini
[Service]
ExecStart=/usr/local/bin/start-myapp.sh
User=deploy
```

## 7. Editing secrets later

```bash
# Opens decrypted content in $EDITOR, re-encrypts on save
sops secrets/shared.env
```

That's it. Only machines whose keys are listed in `.sops.yaml` can decrypt.

## 8. Adding a new machine

1. Generate an age key on the new machine (step 2)
2. Add its public key to the relevant rules in `.sops.yaml`
3. Re-encrypt existing files so the new key can decrypt them:

```bash
# updatekeys reads .sops.yaml and re-encrypts for the current key list
sops updatekeys secrets/shared.env
sops updatekeys secrets/prod.env
```

4. Commit and push

## 9. Removing a machine

1. Remove its public key from `.sops.yaml`
2. Run `sops updatekeys` on every affected file
3. **Rotate any secrets** the machine had access to (the old machine could have
   cached them)

---

## Quick reference

| Task                        | Command                                    |
| --------------------------- | ------------------------------------------ |
| Create/edit encrypted file  | `sops secrets/shared.env`                  |
| Decrypt to stdout           | `sops -d secrets/shared.env`               |
| Run command with secrets    | `sops exec-env secrets/shared.env 'cmd'`   |
| Encrypt existing file       | `sops --encrypt --in-place file.env`       |
| Add/remove keys & re-encrypt| `sops updatekeys secrets/shared.env`       |
| Show which keys can decrypt | `sops filestatus secrets/shared.env`       |
