# Deploy Cab Booking to AWS (EC2) with GitHub Actions — from scratch

Flow: `git push main` → GitHub Actions runs tests → builds Docker image → pushes to GitHub Container Registry (GHCR) → SSHes into your EC2 server → `docker compose up -d`.

Files involved: `Dockerfile`, `docker-compose.prod.yml`, `nginx.conf`, `.env` (on server only), `.github/workflows/deploy.yml`.

---
## PART 1 — Create the AWS account
1. Go to https://aws.amazon.com → **Create an AWS account**.
2. Enter email, account name, verify email, set a password.
3. Choose **Personal** account, fill in name/address/phone.
4. Add a credit/debit card (needed for verification; international cards with online payments enabled work). A small temporary hold may appear.
5. Verify phone (SMS/call), then choose the **Free plan** (new accounts since July 2025 get ~$100 credit, up to $200 with onboarding tasks; the Free plan lasts 6 months or until credits run out, then the account closes unless you upgrade). Older accounts (before 15 Jul 2025) still have 12 months of 750 h/month t2/t3.micro.
6. Sign in to the **AWS Console** as root user.

### Secure it + set a billing alarm (5 minutes)
1. Top-right account menu → **Security credentials** → enable **MFA** on root.
2. Search **Billing** → **Budgets** → Create budget → *Zero spend budget* (or a $5 budget) → enter your email.
3. Top-right, choose the region closest to you (e.g. **Asia Pacific (Mumbai) ap-south-1**). Stay in the same region for everything.

---
## PART 2 — Launch the EC2 server
1. Console → search **EC2** → **Launch instance**.
2. **Name:** `cab-booking`.
3. **AMI:** Ubuntu Server 24.04 LTS (64-bit x86).
4. **Instance type:** `t3.micro` (1 GB RAM, free-tier eligible). If it feels slow/out of memory, use `t3.small` (2 GB) — it is cheap and covered by credits on the new Free plan.
5. **Key pair:** *Create new key pair* → name `cab-key`, type RSA, format `.pem` → it downloads. **Keep this file safe**; you need it for GitHub.
6. **Network settings → Edit:** create security group with:
   - SSH (22) → Source: **My IP** (GitHub Actions needs to reach SSH too, so for the deploy to work set SSH to **Anywhere 0.0.0.0/0**. Safe enough because only your key can log in; password login is disabled by default).
   - HTTP (80) → Anywhere.
   - HTTPS (443) → Anywhere.
7. **Storage:** 20 GiB gp3.
8. **Launch instance.**
9. **Elastic IP (so the IP never changes):** EC2 → *Elastic IPs* → Allocate → Associate with your instance. Note this IP, e.g. `13.233.x.x`. (Release it if you delete the server, otherwise it can be billed.)

---
## PART 3 — Prepare the server (one time)
On your laptop (Linux/Mac/Git-Bash; on Windows PowerShell use `ssh` the same way):
```bash
chmod 400 cab-key.pem
ssh -i cab-key.pem ubuntu@<ELASTIC_IP>
```
On the server:
```bash
# Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 curl
sudo usermod -aG docker ubuntu
exit      # log out and SSH in again so the group applies
```
SSH back in, then:
```bash
# Swap (important on 1 GB RAM)
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# App folder and secrets
mkdir -p ~/cab && cd ~/cab
nano .env
```
Paste into `.env` (use your own values; generate a secret with `openssl rand -hex 48`):
```
POSTGRES_PASSWORD=ChooseAStrongDbPassword
JWT_SECRET=<paste output of openssl rand -hex 48>
ADMIN_EMAIL=admin@cab.com
ADMIN_PASSWORD=ChooseAStrongAdminPassword
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=
SPRING_PROFILES_ACTIVE=
```
Save (Ctrl+O, Enter, Ctrl+X). Leave Stripe blank = demo payment mode.

---
## PART 4 — GitHub repository
1. Create account at https://github.com → **New repository** → name `cab-booking` → Private or Public → Create.
2. On your laptop, in the project folder:
```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/cab-booking.git
git push -u origin main
```
(Do this AFTER step 5 below if you want the first push to deploy straight away.)

3. **Add secrets:** Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Name | Value |
|---|---|
| `EC2_HOST` | your Elastic IP |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | open `cab-key.pem` in a text editor and paste the **entire** content including `-----BEGIN ... KEY-----` and `-----END ... KEY-----` lines |

4. **Allow workflow to publish packages:** Settings → Actions → General → Workflow permissions → **Read and write permissions** → Save.

---
## PART 5 — Deploy
1. Push to `main` (or Actions tab → **Deploy** → *Run workflow*).
2. Watch Actions tab: `test` → `build-and-push` → `deploy` (first run takes ~8–12 min).
3. Open `http://<ELASTIC_IP>/` in the browser. Health check: `http://<ELASTIC_IP>/actuator/health` should show `{"status":"UP"}`.
4. Admin login: the `ADMIN_EMAIL` / `ADMIN_PASSWORD` from your `.env`.

Every later `git push` to `main` redeploys automatically. Pull requests / other branches only run `ci.yml` (tests + build).

---
## Troubleshooting
| Problem | Fix |
|---|---|
| `deploy` fails: *ssh: handshake failed / timeout* | Security group SSH rule must allow GitHub (0.0.0.0/0); check `EC2_HOST` and the full key pasted. |
| `permission denied` for docker | Re-login after `usermod -aG docker ubuntu`. |
| `denied` pulling the image | Settings → Actions → Workflow permissions must be Read **and write**; re-run workflow. |
| App container restarting / killed | Out of memory: check swap with `free -h`, or move to `t3.small`. |
| See logs | `ssh` in → `cd ~/cab && docker compose -f docker-compose.prod.yml logs -f app` |
| Site not opening | Security group must allow port 80; `docker compose -f docker-compose.prod.yml ps` |

## Useful commands on the server
```bash
cd ~/cab
export APP_IMAGE=$(docker inspect -f '{{.Config.Image}}' cab-app-1)   # only needed for manual compose commands
docker compose -f docker-compose.prod.yml --env-file .env ps
docker compose -f docker-compose.prod.yml --env-file .env restart app
```

## Cost control / cleanup
- Check **Billing → Free Tier** monthly.
- To stop all charges: EC2 → terminate instance, release the Elastic IP, delete the volume.
- Free plan: the account closes after 6 months or when credits are used up — export anything you need before that.

## Optional later
- **HTTPS:** needs a domain (e.g. free subdomain from DuckDNS or a cheap domain) + certificate (Let's Encrypt). Required for Stripe webhooks and Google login in real use.
- **Managed DB:** use Supabase/RDS and set `DB_URL`, `DB_USER`, `DB_PASSWORD` (remove the `db` service from `docker-compose.prod.yml`).
