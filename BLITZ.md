# Blitz fork of LandSandBoat

fork นี้คือโค้ด LandSandBoat ที่ใช้รันเซิร์ฟเวอร์ Blitz FFXI (ffxi.blitz.monster) มีไว้แก้ bug (รวมถึง C++) และเพิ่มคอนเทนต์ที่ทำเป็น module ไม่ได้ แล้ว merge update จาก [LandSandBoat/server](https://github.com/LandSandBoat/server) เข้ามาทุกสัปดาห์

ไฟล์นี้และ `.github/workflows/blitz-*.yml` ไม่มีใน LSB จึงไม่ชนตอน merge ห้ามแก้ไฟล์ของ LSB ถ้าไม่จำเป็น เพราะทุกบรรทัดที่แก้มีโอกาสชนกับ update ของ LSB

## Branch

| branch | ใช้ทำอะไร |
|---|---|
| `blitz` | branch หลักที่ deploy ทุกการเปลี่ยนแปลงเข้ามาทาง PR เท่านั้น และต้องเทสต์ผ่านก่อน |
| `sync/upstream-YYYYMMDD` | สร้างอัตโนมัติทุกสัปดาห์ ใช้ merge LSB เข้ามา |
| `fix/...`, `feature/...` | งานของเรา แตกจาก `blitz` |
| `base` | ของเดิมตอน fork ไม่ได้ใช้ (ใช้ `upstream/base` แทน) |

**merge เท่านั้น ห้าม rebase หรือ squash** dbtool ใน image ไล่ประวัติ git จาก commit ที่ฐานข้อมูลอัปเดตล่าสุด (`db_ver`) ถ้า commit นั้นหายจากประวัติ การอัปเดตฐานข้อมูลจะพัง repo นี้จึงเปิดให้ merge แบบ merge commit อย่างเดียว และห้ามลบหรือ rename repo เพราะ image ดึง git จาก URL นี้ตลอด

## Workflow

| ไฟล์ | ทำงานเมื่อ | ทำอะไร |
|---|---|---|
| `blitz-pr.yml` | เปิด/อัปเดต PR เข้า `blitz` | build image (ไม่ publish) แล้วเทสต์ด้วย docker test ของ LSB (dbtool, xi_test, startup checks) ผลรวมอยู่ใน check **Blitz PR gate** ซึ่ง ruleset บังคับให้ผ่านก่อน merge |
| `blitz-image.yml` | push เข้า `blitz` (หรือกด Run บน `blitz` เท่านั้น) | build แล้ว publish `ghcr.io/bermmerb/server`, เทสต์, ผ่านแล้วติดป้าย `:release` เฉพาะเมื่อ commit นี้ยังเป็นยอดของ `blitz` และ image ที่เทสต์คือ image ของ commit นี้ (re-run ของรอบเก่าจะไม่ย้าย `:release` ถอยหลัง) |
| `blitz-sync.yml` | ทุกวันเสาร์ 02:00 (เวลาไทย ก่อน auto-update ของ VM วันอาทิตย์ 03:00 หนึ่งวัน) หรือกดเอง | merge `LandSandBoat/server` base เข้า branch sync แล้วเปิด PR ที่ merge ตัวเองเมื่อ Blitz PR gate ผ่าน ถ้าชนจะ fail และบอกไฟล์ที่ชนใน summary ถ้า LSB เพิ่มหรือ rename ไฟล์ workflow จะเปิด PR แบบไม่ auto-merge แล้ว fail ให้คนมาดูก่อน |
| `blitz-retry.yml` | Blitz Image/PR fail | รันงานที่ fail ซ้ำ 1 ครั้ง (xi_test ของ LSB ล้มแบบสุ่มเป็นบางครั้ง) |
| `blitz-guard.yml` | ไฟล์ workflow บน `blitz` เปลี่ยน | ปิด workflow อื่นทั้งหมดยกเว้น `blitz-*` และ reusable ที่เราเรียกใช้ (`docker_build`, `docker_test`, `runner_build`, `runner_test`) |

workflow เดิมของ LSB (Builds, Tests, PR Checks, CodeQL, ...) ถูกปิดไว้ใน fork นี้

## Image tag

- `:release` ตัวที่เทสต์ผ่านล่าสุด **VM เกมดึงตัวนี้เท่านั้น** (ผ่าน auto-update ทุกสัปดาห์ มี backup และ rollback)
- `:release-YYYYMMDD-<sha>` ประวัติของแต่ละ release
- `:latest`, `:blitz`, `:sha-<sha>` push ตอน build ก่อนเทสต์ ห้ามให้ VM ใช้

## Secret และค่าที่ตั้งไว้

- secret `BLITZ_SYNC_TOKEN` อยู่ใน environment `upstream-sync` (ใช้ได้เฉพาะ branch `blitz` workflow บน branch sync หรือ PR จึงมองไม่เห็น) เป็น fine-grained token เฉพาะ repo นี้ สิทธิ์ Contents, Pull requests, Workflows (read/write) ใช้โดย `blitz-sync.yml` เท่านั้น หมดอายุแล้วต้องสร้างใหม่ (`gh secret set BLITZ_SYNC_TOKEN --env upstream-sync -R bermmerb/server`)
- variable `PUBLISH_DOCKER=1`: ให้ `docker_build.yml` ของ LSB push image ขึ้น ghcr

## ตั้งค่าครั้งแรก (ทำตามลำดับนี้)

1. เปิด Actions ของ fork (หน้า Actions กด enable) แล้วปิด workflow ของ LSB ทั้งหมดยกเว้น reusable 4 ตัว
2. ตั้งค่า repo: variable `PUBLISH_DOCKER=1`, merge แบบ merge commit อย่างเดียว, เปิด auto-merge, Workflow permissions ค่าเริ่มต้นเป็น read-only, ต้องอนุมัติก่อน workflow ของคนนอกจะรัน
3. สร้าง branch `blitz` ที่ revision ที่เซิร์ฟเวอร์รันอยู่ (ยังไม่มีไฟล์ `blitz-*`) แล้วตั้งเป็น default branch ก่อน push ไฟล์ `blitz-*` (ไม่อย่างนั้นรอบแรกจะไม่ได้ tag `:latest`)
4. push commit ที่มีไฟล์ `blitz-*` เข้า `blitz` รอบแรก Test จะ fail เพราะ package ใหม่เป็น private (retry อัตโนมัติก็ fail เหมือนกัน เป็นเรื่องปกติ)
5. ตั้ง package `ghcr.io/bermmerb/server` เป็น public (Package settings → Change visibility) แล้ว Re-run failed jobs ของรอบนั้น `:release` ตัวแรกจะเกิดตอนนี้
6. สร้าง environment `upstream-sync` (deployment branch: `blitz` เท่านั้น) แล้วใส่ secret `BLITZ_SYNC_TOKEN` ในนั้น
7. สร้าง ruleset บน `blitz`: ต้องผ่าน PR, required check `Blitz PR gate` (จาก GitHub Actions), ห้าม force-push และห้ามลบ ไม่มีใคร bypass ได้
8. กด Run workflow ที่ Blitz Upstream Sync เพื่อ sync รอบแรก

## ห้ามขึ้น repo นี้

repo นี้เป็น public และสิ่งที่ push ขึ้นไปแล้วลบออกจากประวัติไม่ได้จริง ห้ามใส่รหัสผ่าน `.env` IP ในวงแลน ข้อมูลผู้เล่น หรือตัวแก้ช่องโหว่ที่ยังไม่ได้แจ้ง LSB สิ่งเหล่านี้อยู่ใน repo private `bermmerb/ffxi-server`

## sync เอง (ถ้า workflow ชน)

```bash
git fetch upstream base
git switch blitz && git pull
git switch -c sync/manual-YYYYMMDD
git merge upstream/base        # แก้ไฟล์ที่ชน แล้ว git commit
git push -u origin HEAD        # เปิด PR เข้า blitz รอเทสต์ผ่านแล้ว merge
```

## ส่งแก้กลับเข้า LSB

แตก branch จาก `upstream/base` (ไม่ใช่ `blitz`) แล้วเปิด PR ไปที่ LandSandBoat/server อ่าน [CONTRIBUTING.md](CONTRIBUTING.md) และ [docs/ai_agents/README.md](docs/ai_agents/README.md) ก่อน: ต้องเทสต์ในเกมจริง อ้างอิง retail และเขียนคำอธิบาย PR เอง
