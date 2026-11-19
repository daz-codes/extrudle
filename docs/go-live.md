# Go-live checklist

In order. Tick each step off as it's done.

## 1. Server and backups
- [ ] Choose the server and point a host name at it (e.g. `erp.<stu's domain>`).
- [ ] Set up the Cloudflare R2 bucket and token (see [backups.md](backups.md)).
- [ ] Deploy with `DEPLOY_HOST`, `APP_HOST`, the Litestream variables, `ADMIN_EMAIL` and `ADMIN_PASSWORD` set.
  - The first admin is created from `ADMIN_EMAIL` and can sign in from any computer.
  - Only approved computers can use the system (`REQUIRE_APPROVED_COMPUTERS` is on).
- [ ] **Users › Backups › Check now** passes.
- [ ] Run `bin/backup-drill` against a copy of the server's database.

## 2. Company details and settings
- [ ] Real company details in `config/company.yml` (PLAN.md §11 Q19).
- [ ] Sage nominal code and VAT rates in `config/sage.yml` (Q63).
- [ ] Lines, changeover times and line rates (Q2, Q3).

## 3. Data, under Master data › Import
In this order, because each step uses the ones before:
1. [ ] Suppliers
2. [ ] Materials (the five standard categories are created with the first admin; add others under Master data › Categories first)
3. [ ] Customers, with Sage account references and VAT codes
4. [ ] Product specs, with a rate column per line, then each spec's recipe if it differs from the standard (Q6)
5. [ ] Opening stock: count every bag on site, import, then print and stick on the labels (Q32)

## 4. People and computers
- [ ] Add every user under **Users**, as Admin, Office or Floor.
- [ ] Approve each computer: sign in on it with the first admin, then **Users › Computers › Approve this computer**. Give each one a clear name (D1 floor screen, Office PC…).
- [ ] Print a stack of blank logs for each line (**Production › Blank paper log**), in case the system is down.

## 5. Training
- [ ] Walk the floor through **Help**: start a log, load material, enter reels, finish a log, and what to do if the system is down.
- [ ] Walk the office through orders, the planner (and draft plans), purchasing, goods in, dispatch and the Sage export.
- [ ] Run the first week on paper and in Extrudle side by side, then compare the logs.

## 6. First live day
- [ ] Set the first despatch number when starting the first log: the next number after the paper logs (Q33).
- [ ] Publish the first plan.
- [ ] Do the first Sage export at the end of the week, and check it in Sage.
