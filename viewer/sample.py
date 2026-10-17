#!/usr/bin/env python3
"""Writes a made-up recording that uses every record type, for trying out the viewer.

Usage: sample.py [out.jsonl]     (default: stdout)

A TMF platoon (two squads and a car) attacks an AI-held village; a few players connect,
take units, fire, get hit, drive, place and draw markers (with a Cover Map module), talk on ACRE2 radios and leave. Not real data.
"""
import json
import math
import random
import sys

rnd = random.Random(7)
lines = []


def rec(t, type_, **f):
    lines.append({"type": type_, "t": round(t, 3), **f})


DURATION = 420
INTERVAL = 1
KEY = 60
X0, Y0 = 3600.0, 5500.0            # BLUFOR start, in the hills south-east of the village
VX, VY = 3000.0, 6000.0            # village centre (Agia Marina, Stratis)

rec(0, "header", version=1, mission="co12_village_raid", world="Stratis",
    started_utc="2026-10-13T19:00:00Z", interval=INTERVAL, keyframe_interval=KEY, multiplayer=True,
    briefing_name="CO12 Village Raid", on_load_name="Village Raid", author="Sample Author",
    overview="Clear Agia Marina and hold it until the convoy arrives.",
    game_type="Coop", max_players=12, server_name="Sample Server #1", world_name="Stratis",
    world_size=8192, date=[2035, 6, 12, 5, 40], time_multiplier=1, weather=[0.35, 0.05, 0],
    game_version=[2.22, 152948], mods=["TMF", "CBA_A3", "ACE"])

rec(0, "orbat", source="tmf", teams=[
    {"side": "WEST", "id": 0, "name": "1 PLT", "full_name": "1st Platoon", "icon": "x\\tmf\\addons\\orbat\\textures\\yellow_inf.paa",
     "modifier": "x\\tmf\\addons\\orbat\\textures\\modif_3dot.paa", "order": 0, "children": [
         {"id": 1, "name": "PLT HQ", "full_name": "Platoon HQ", "icon": "", "modifier": "", "order": 0, "children": []},
         {"id": 2, "name": "A", "full_name": "Alpha Squad", "icon": "x\\tmf\\addons\\orbat\\textures\\red_inf.paa", "modifier": "x\\tmf\\addons\\orbat\\textures\\modif_dot.paa", "order": 1, "children": [
             {"id": 4, "name": "A1", "full_name": "Alpha 1", "icon": "", "modifier": "", "order": 0, "children": []},
             {"id": 5, "name": "A2", "full_name": "Alpha 2", "icon": "", "modifier": "", "order": 1, "children": []}]},
         {"id": 3, "name": "B", "full_name": "Bravo Squad", "icon": "", "modifier": "", "order": 2, "children": []},
         {"id": 6, "name": "Hunter 1", "full_name": "Hunter 1 (MRAP)", "icon": "", "modifier": "", "order": 3, "children": []}]},
    {"side": "EAST", "id": 100, "name": "Garrison", "full_name": "Agia Marina Garrison", "icon": "x\\tmf\\addons\\orbat\\textures\\red_inf.paa", "modifier": "x\\tmf\\addons\\orbat\\textures\\modif_2dot.paa", "order": 0, "children": []},
])

# TMF ACRE2 radio network: the platoon net on the 152s, one 343 channel per squad.
rec(0, "radio_nets", source="tmf", nets=[
    {"index": 0, "sides": ["WEST"], "factions": [], "channels": [
        {"name": "PLTNET", "description": "Platoon net", "radio": "ACRE_PRC152", "shared": False, "number": 1, "freq": 60.15},
        {"name": "ALPHA", "description": "Alpha squad", "radio": "ACRE_PRC343", "shared": False, "number": 1, "freq": 2400.13},
        {"name": "BRAVO", "description": "Bravo squad", "radio": "ACRE_PRC343", "shared": False, "number": 2, "freq": 2400.23},
        {"name": "FIRES", "description": "Fire support", "radio": "ACRE_PRC152", "shared": True, "number": 2, "freq": 61.15},
        {"name": "LOGNET", "description": "Logistics", "radio": "ACRE_PRC152", "shared": False, "number": 3, "freq": 62.15}]},
    # Preset nobody used: hidden in the Radio tab until "Show unused" is ticked.
    {"index": 1, "sides": ["EAST"], "factions": [], "channels": [
        {"name": "COY", "description": "Company net", "radio": "ACRE_PRC148", "shared": False, "number": 1, "freq": 50.15}]},
])
SHORT = {"PLT HQ": "HQ", "Alpha 1": "A1", "Alpha 2": "A2", "Bravo": "B"}
# TMF_groupMarker textures: [icon, size]
TEX = "x\\tmf\\addons\\orbat\\textures\\"
ICON = {"PLT HQ": (TEX + "yellow_hq.paa", ""), "Alpha 1": (TEX + "red_inf.paa", TEX + "modif_o.paa"),
        "Alpha 2": (TEX + "red_inf.paa", TEX + "modif_o.paa"), "Bravo": (TEX + "blue_inf.paa", TEX + "modif_dot.paa")}
CHANNELS = {"PLT HQ": [0, 3], "Alpha 1": [1], "Alpha 2": [1], "Bravo": [2]}

# --- entities -------------------------------------------------------------------------------
units = {}   # id -> dict(x, y, dir, alive, dmg, veh, side)
nid = 1
roles = [("sl", "Squad Leader"), ("ftl", "Team Leader"), ("ar", "Autorifleman"), ("r", "Rifleman"), ("lat", "Rifleman (AT)"), ("m", "Medic")]
west_groups = [("PLT HQ", 1, 2), ("Alpha 1", 4, 4), ("Alpha 2", 5, 4), ("Bravo", 3, 4)]
players = {1: ("76561190000000001", "Sebastian"), 2: ("76561190000000002", "Kim"), 6: ("76561190000000003", "Alex")}
for gi, (gname, node, n) in enumerate(west_groups):
    for k in range(n):
        role = roles[k % len(roles)] if gname != "PLT HQ" else [("pl", "Platoon Leader"), ("rto", "Radio Operator")][k]
        uid, name = players.get(nid, ("", f"{gname} {k + 1}"))
        x = X0 + gi * 30 + k * 6
        y = Y0 + k * 5
        units[nid] = dict(x=x, y=y, dir=45, alive=True, dmg=0.0, veh=0, side="WEST", group=gname)
        rec(1, "entity", id=nid, kind="unit", **{"class": "B_Soldier_F"}, display="Rifleman", side="WEST",
            name=name if not uid else "AI " + str(nid), group=gname, player=False, uid="", orbat=node,
            group_short=SHORT[gname], group_icon=ICON[gname][0], group_size=ICON[gname][1], radio_net=0, radio_channels=CHANNELS[gname] + ([0] if k == 0 else []),
            loadout_faction="blu_f", role=role[0], role_name=role[1])
        if k == 0:
            rec(1, "leader", unit=nid, group=gname, side="WEST")
        nid += 1
car = nid; nid += 1
units[car] = dict(x=X0 - 40, y=Y0 - 20, dir=45, alive=True, dmg=0.0, veh=0, side="WEST", group="")
rec(1, "entity", id=car, kind="car", **{"class": "B_MRAP_01_hmg_F"}, display="Hunter HMG", side="WEST", orbat=6, callsign="Hunter 1", orbat_team="WEST")
east = []
for g in range(2):
    for k in range(5):
        a = rnd.random() * math.tau
        x, y = VX + math.cos(a) * rnd.uniform(20, 120), VY + math.sin(a) * rnd.uniform(20, 120)
        units[nid] = dict(x=x, y=y, dir=rnd.uniform(0, 360), alive=True, dmg=0.0, veh=0, side="EAST", group=f"Garrison {g + 1}")
        rec(1, "entity", id=nid, kind="unit", **{"class": "O_Soldier_F"}, display="Rifleman", side="EAST",
            name=f"Garrison {g + 1}-{k + 1}", group=f"Garrison {g + 1}", player=False, uid="")
        east.append(nid); nid += 1
static = nid; nid += 1
units[static] = dict(x=VX + 30, y=VY - 10, dir=200, alive=True, dmg=0.0, veh=0, side="EAST", group="")
rec(1, "entity", id=static, kind="static", **{"class": "O_HMG_01_high_F"}, display="Mk30 HMG", side="EAST")
west = [i for i, u in units.items() if u["side"] == "WEST" and i != car]

for g in range(2):
    rec(1, "leader", unit=east[g * 5], group=f"Garrison {g + 1}", side="EAST")
    rec(1, "combat_mode", group=f"Garrison {g + 1}", side="EAST", leader=east[g * 5], mode="SAFE")

# --- timeline -------------------------------------------------------------------------------
events = []   # (t, type, fields) added below, merged in time order


def ev(t, type_, **f):
    events.append((t, type_, f))


for pid, (uid, name) in players.items():
    jt = 2 + pid
    ev(jt, "connected", uid=uid, name=name, jip=pid == 6, owner=2 + pid)
    ev(jt + 0.5, "player", unit=pid, uid=uid, name=name)
    ev(jt + 3, "loadout", unit=pid, loadout_faction="blu_f", role=["pl", "rto", "", "", "", "sl"][pid - 1] or "r",
       role_name=["Platoon Leader", "Radio Operator", "", "", "", "Squad Leader"][pid - 1] or "Rifleman")
def marker(text="", type_="mil_dot", color="Default", shape="ICON", brush="Solid", size=(1, 1), dir=0, alpha=1, **f):
    return dict(text=text, markerType=type_, color=color, shape=shape, brush=brush, size=list(size), dir=dir, alpha=alpha, **f)


# Placed in the editor: the AO, the objective area, the start point and a phase line.
ev(0, "marker_created", marker="ao", channel=-1, editor=True, pos=[VX + 250, VY - 150, 0],
   **marker(shape="RECTANGLE", brush="Border", color="ColorBlack", size=(900, 650), dir=15))
ev(0, "marker_created", marker="obj_area", channel=-1, editor=True, pos=[VX, VY, 0],
   **marker(shape="ELLIPSE", brush="FDiagonal", color="ColorOPFOR", size=(160, 120)))
ev(0, "marker_created", marker="start", channel=-1, editor=True, pos=[X0, Y0, 0], **marker("START", "mil_start", "ColorBLUFOR"))
ev(0, "marker_created", marker="pl_blue", channel=-1, editor=True, pos=[X0 - 300, Y0 + 250, 0],
   **marker("PL BLUE", "mil_dot", "ColorBLUFOR", shape="POLYLINE",
            line=[X0 - 500, Y0 + 50, X0 - 350, Y0 + 260, X0 - 120, Y0 + 420, X0 + 60, Y0 + 640]))
# The Cover Map module: everything outside the AO is shaded.
ev(0, "cover_map", id="0", pos=[VX + 250, VY - 150, 0], area=[1000, 750, 15])
# Placed by players during the mission.
ev(20, "marker_created", marker="_USER_DEFINED #2/0/1", channel=1, owner=1, pos=[VX, VY, 0], **marker("OBJ MARINA", "mil_objective", "ColorRed"))
ev(22, "marker_created", marker="_USER_DEFINED #2/1/1", channel=3, owner=1, pos=[X0 + 300, Y0 + 280, 0], **marker("RP", "mil_dot", "ColorBLUFOR"))
ev(60, "marker_created", marker="_USER_DEFINED #2/2/1", channel=3, owner=1, pos=[X0 - 150, Y0 + 500, 0],
   **marker("ATK", "mil_arrow", "ColorBLUFOR", dir=300, size=(1.5, 1.5)))
ev(75, "marker_created", marker="_USER_DEFINED #2/3/1", channel=3, owner=1, pos=[VX + 200, VY - 120, 0],
   **marker("", "mil_dot", "ColorOrange", shape="POLYLINE", line=[X0 - 100, Y0 + 350, VX + 400, VY - 250, VX + 200, VY - 120]))
ev(140, "marker_updated", marker="_USER_DEFINED #2/1/1", pos=[X0 + 420, Y0 + 380, 0], **marker("RP (moved)", "mil_dot", "ColorBLUFOR"))
ev(320, "marker_updated", marker="obj_area", pos=[VX, VY, 0],
   **marker(shape="ELLIPSE", brush="FDiagonal", color="ColorBLUFOR", size=(160, 120)))
ev(30, "get_in", vehicle=car, unit=6, role="driver")
ev(31, "get_in", vehicle=car, unit=7, role="gunner")
ev(31, "get_in", vehicle=car, unit=8, role="cargo")
ev(95, "seat", vehicle=car, unit=8, role="gunner")
ev(96, "get_out", vehicle=car, unit=6, role="driver")
ev(150, "get_out", vehicle=car, unit=8, role="gunner", eject=True)
ev(110, "group", unit=10, group="Alpha 1", side="WEST", orbat=4, group_short="A1", group_icon=ICON["Alpha 1"][0], group_size=ICON["Alpha 1"][1])
ev(380, "marker_deleted", marker="_USER_DEFINED #2/0/1", by=1)
ev(300, "building", **{"from": "Land_i_House_Small_02_V1_F", "to": "Land_i_House_Small_02_V1_ruins_F"}, ruin=True, pos=[VX + 40, VY + 15, 12])
ev(118, "enemy_detected", group="Garrison 1", side="EAST", leader=east[0], target=1)
ev(118.2, "combat_mode", group="Garrison 1", side="EAST", leader=east[0], mode="COMBAT")
ev(124, "enemy_detected", group="Garrison 2", side="EAST", leader=east[5], target=car)
ev(124.3, "combat_mode", group="Garrison 2", side="EAST", leader=east[5], mode="COMBAT")
ev(260, "fleeing", group="Garrison 2", side="EAST", leader=east[5], fleeing=True)
ev(290, "fleeing", group="Garrison 2", side="EAST", leader=east[5], fleeing=False)
# Chat on several channels: what players typed, plus a system message the server saw.
for t, ch, pid, text in ((14, 0, 2, "o7 all"), (30, 1, 1, "Platoon, step off in 2 mikes"), (31, 3, 6, "Alpha copies"),
                         (44, 5, 2, "you got my back on the left?"), (90, 4, 6, "driver, stop at the treeline"),
                         (131, 2, 1, "Contact east, marina. Bravo push north"), (262, 1, 2, "they're running"),
                         (330, 3, 6, "anyone need ammo?"), (395, 0, 1, "gg, ENDEX")):
    ev(t, "chat", channel=ch, text=text, unit=pid, name=players[pid][1], player=True)
ev(200, "chat", channel=6, channel_name="Fires", text="Mortars ready", unit=2, name="Kim", player=True)
ev(410, "chat", channel=16, text="Kim was kicked off by BattlEye: Client not responding")
# Radios: what each player carries, a retune, and transmissions (ACRE2 reports start and end).
def radio(rid, cls, name, ch, freq, label):
    return {"radio_id": rid, "radio": cls, "radio_name": name, "channel": ch, "freq": freq, "channel_name": label}
kit = {
    1: [radio("acre_prc152_id_1", "ACRE_PRC152", "AN/PRC-152", 1, 60.15, "01 - PLTNET"), radio("acre_prc343_id_1", "ACRE_PRC343", "AN/PRC-343", 1, 2400.13, "Block 1 - Channel 01")],
    2: [radio("acre_prc117f_id_1", "ACRE_PRC117F", "AN/PRC-117F", 1, 60.15, "PLTNET"), radio("acre_prc152_id_2", "ACRE_PRC152", "AN/PRC-152", 2, 61.15, "02 - FIRES")],
    6: [radio("acre_prc152_id_3", "ACRE_PRC152", "AN/PRC-152", 1, 60.15, "01 - PLTNET"), radio("acre_prc343_id_2", "ACRE_PRC343", "AN/PRC-343", 2, 2400.23, "Block 1 - Channel 02")],
}
for pid, radios in kit.items():
    ev(8 + pid, "radios", unit=pid, system="acre", radios=radios)
# Alex retunes the 343 to Alpha's channel when Bravo joins the assault.
ev(112, "radios", unit=6, system="acre", radios=[kit[6][0], radio("acre_prc343_id_2", "ACRE_PRC343", "AN/PRC-343", 1, 2400.13, "Block 1 - Channel 01")])
tx_t = 25.0
while tx_t < 380:
    pid = rnd.choice([1, 1, 2, 6])
    r = rnd.choice(kit[pid])
    if pid == 6 and r["radio"] == "ACRE_PRC343" and tx_t > 112:
        r = dict(r, channel=1, freq=2400.13, channel_name="Block 1 - Channel 01")
    if units[pid]["alive"]:
        length = round(rnd.uniform(1.2, 7.5), 2)
        f = {k: r[k] for k in ("radio_id", "radio", "radio_name", "channel", "freq", "channel_name")}
        ev(tx_t, "radio_tx", unit=pid, system="acre", **f)
        ev(tx_t + length, "radio_tx_end", unit=pid, system="acre", radio_id=r["radio_id"])
    tx_t += rnd.uniform(4, 18) if 110 < tx_t < 300 else rnd.uniform(15, 40)
ev(395, "disconnected", uid=players[2][0], name=players[2][1], jip=False, owner=4)
ev(395.2, "player", unit=2, uid="", name="")

# Kills and deaths decided up front so movement and shots line up with them.
kill_plan = {east[0]: 150, east[1]: 162, east[2]: 175, east[3]: 190, east[5]: 210, east[6]: 228, static: 240,
             east[7]: 270, 11: 185, 14: 233}
respawn_at = {11: 215}

shot_id = 1
west_target = lambda t: (min(1.0, max(0.0, (t - 40) / 160)))
pending = []
for t10 in range(10, DURATION * 10):
    t = t10 / 10
    # movement
    f = west_target(t)
    for i in west + [car]:
        u = units[i]
        if not u["alive"]:
            continue
        tx = X0 + (VX - 90 - X0) * f + (i % 5) * 9
        ty = Y0 + (VY - 70 - Y0) * f + (i % 4) * 7
        if i == car:
            tx, ty = (tx + 60, ty - 40) if t < 96 else (u["x"], u["y"])
        dx, dy = tx - u["x"], ty - u["y"]
        d = math.hypot(dx, dy)
        sp = (6 if i == car else 1.6) * 0.1
        if d > 0.5:
            u["x"] += dx / d * min(d, sp); u["y"] += dy / d * min(d, sp)
            u["dir"] = (math.degrees(math.atan2(dx, dy)) + 360) % 360
    for i in east:
        u = units[i]
        if u["alive"] and t > 118 and t10 % 30 == 0:
            u["dir"] = (math.degrees(math.atan2(X0 - u["x"], Y0 - u["y"])) + rnd.uniform(-20, 20)) % 360
    # firefight 120..300
    if 120 <= t <= 300 and t10 % 3 == 0:
        live_w = [i for i in west if units[i]["alive"] and not units[i]["veh"]]
        live_e = [i for i in east + [static] if units[i]["alive"]]
        if live_w and live_e and rnd.random() < 0.8:
            side = rnd.random() < 0.6
            a, b = (rnd.choice(live_w), rnd.choice(live_e)) if side else (rnd.choice(live_e), rnd.choice(live_w))
            ua, ub = units[a], units[b]
            dist = math.hypot(ub["x"] - ua["x"], ub["y"] - ua["y"])
            v = 880
            vel = [(ub["x"] - ua["x"]) / dist * v, (ub["y"] - ua["y"]) / dist * v, 2]
            tof = dist / v
            hit = rnd.random() < 0.08
            end = [ub["x"] + (0 if hit else rnd.uniform(-8, 8)), ub["y"] + (0 if hit else rnd.uniform(-8, 8)), 20]
            weapon, ammo = ("arifle_MX_F", "B_65x39_Caseless") if units[a]["side"] == "WEST" else ("arifle_Katiba_F", "B_65x39_Caseless_green")
            if a == static:
                weapon, ammo = "HMG_static", "B_127x99_Ball_Tracer_Red"
            ev(t, "shot", id=shot_id, shooter=a, weapon=weapon, ammo=ammo, pos=[round(ua["x"], 1), round(ua["y"], 1), 21.5], vel=[round(x, 1) for x in vel])
            if hit:
                ev(t + tof, "proj_hit", id=shot_id, target=b, pos=[round(x, 1) for x in end], part=rnd.choice(["spine3", "head", "leftleg", "arms"]))
                ev(t + tof + 0.01, "hit", unit=b, source=a, instigator=a, damage=round(rnd.uniform(0.2, 0.6), 2))
            ev(t + tof, "proj_end", id=shot_id, pos=[round(x, 1) for x in end], exploded=False)
            shot_id += 1
    # grenades / AT
    if t in (205.0, 236.0):
        a = 5 if t == 205 else 9
        ua = units[a]; tgt = static if t == 236 else east[5]
        ub = units[tgt]
        ev(t, "shot", id=shot_id, shooter=a, weapon="launch_NLAW_F" if t == 236 else "Throw", ammo="M_NLAW_AT_F" if t == 236 else "GrenadeHand",
           pos=[round(ua["x"], 1), round(ua["y"], 1), 21], vel=[0, 0, 0])
        ev(t + 2.5, "proj_splash", id=shot_id, target=tgt)
        ev(t + 2.5, "proj_end", id=shot_id, pos=[round(ub["x"], 1), round(ub["y"], 1), 20], exploded=True)
        shot_id += 1
    if t == 60:   # smoke with submunition
        ev(t, "shot", id=shot_id, shooter=car, instigator=7, weapon="SmokeLauncher", ammo="SmokeLauncherAmmo", pos=[units[car]["x"], units[car]["y"], 22], vel=[0, 30, 10])
        ev(t + 0.4, "shot", id=shot_id + 1, shooter=car, parent=shot_id, weapon="SmokeLauncher", ammo="SmokeShellVehicle", pos=[units[car]["x"], units[car]["y"] + 10, 24], vel=[0, 25, 5])
        ev(t + 0.4, "submunition", id=shot_id + 1, parent=shot_id, shooter=car)
        ev(t + 0.4, "proj_end", id=shot_id, pos=[units[car]["x"], units[car]["y"] + 10, 24], exploded=False)
        ev(t + 30, "proj_end", id=shot_id + 1, pos=[units[car]["x"], units[car]["y"] + 40, 20], exploded=False)
        shot_id += 2
    for vid, kt in kill_plan.items():
        if abs(t - kt) < 0.05 and units[vid]["alive"]:
            u = units[vid]
            killer = rnd.choice([1, 2, 4, 5, 7]) if u["side"] == "EAST" else east[4]
            u["alive"] = False; u["dmg"] = 1.0
            ev(t, "killed", victim=vid, killer=killer, instigator=killer, pos=[round(u["x"], 1), round(u["y"], 1), 20])
    for old, rt in respawn_at.items():
        if abs(t - rt) < 0.05:
            new = nid; nid += 1
            units[new] = dict(x=X0, y=Y0, dir=45, alive=True, dmg=0.0, veh=0, side="WEST", group="Bravo")
            west.append(new)
            ev(t, "entity", id=new, kind="unit", **{"class": "B_Soldier_F"}, display="Rifleman", side="WEST", name="Bravo 1", group="Bravo", player=False, uid="", orbat=3)
            ev(t, "respawn", new=new, old=old)
            ev(t + 60, "deleted", id=old)
    # vehicle crew state for snapshots
    for uid_, vt0, vt1 in ((6, 30, 96), (7, 31, 10_000), (8, 31, 150)):
        units[uid_]["veh"] = car if vt0 <= t < vt1 else 0
        if units[uid_]["veh"]:
            units[uid_]["x"], units[uid_]["y"] = units[car]["x"], units[car]["y"]

    # snapshots, perf
    if t10 % (INTERVAL * 10) == 0:
        key = t10 % (KEY * 10) == 10 or t10 == 10
        idle = t >= 405
        if not idle or key:
            e = [[i, round(u["x"], 2), round(u["y"], 2), 20.5, round(u["dir"]), int(u["alive"]), round(u["dmg"], 2), u["veh"]] for i, u in units.items()]
            ev(t, "snap", key=key, e=e)
        fight = 120 <= t <= 300
        fps = round(max(8, (34 if fight else 47) + rnd.uniform(-4, 4) - (18 if 238 <= t <= 242 else 0)), 1)
        if not idle:
            ev(t, "perf", fps=fps, fps_min=round(fps - rnd.uniform(2, 9), 1), units=sum(1 for u in units.values() if u["alive"]), entities=len(units),
               projectiles=rnd.randint(2, 14) if fight else 0, snap_frames=1 + (len(units) > 30), snap_ms=round(rnd.uniform(0.4, 1.3), 2), snap_max_ms=round(rnd.uniform(0.4, 1.1), 2), batch=100)
for t, ms in ((239.4, 212.5), (240.1, 145.0), (88.2, 118.3)):
    ev(t, "perf_spike", frame_ms=ms, recorder_ms=round(ms * 0.01, 2), fps=round(1000 / ms, 1), units=25, entities=28)
ev(405, "idle", idle=True)
ev(412, "idle", idle=False)
ev(DURATION, "end", reason="ended:END1", entities=len(units))

events.sort(key=lambda e: e[0])
for t, ty, f in events:
    rec(t, ty, **f)

out = "\n".join(json.dumps(o, separators=(",", ":")) for o in lines) + "\n"
if len(sys.argv) > 1:
    open(sys.argv[1], "w", encoding="utf-8").write(out)
else:
    sys.stdout.write(out)
