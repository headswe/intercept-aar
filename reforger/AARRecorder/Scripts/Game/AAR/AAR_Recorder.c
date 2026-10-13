//! A unit or vehicle being recorded, with the state last written to a snapshot.
class AAR_Tracked
{
	IEntity m_Entity;
	DamageManagerComponent m_Damage;
	int m_Id;
	bool m_IsUnit;
	bool m_Sent;
	vector m_Pos;
	float m_Dir;
	bool m_Alive = true;
	float m_DamageValue;
	int m_Vehicle;
	string m_Orbat;
	ref AAR_ShotListener m_Shots;
}

//! Forwards OnProjectileShot from one unit or vehicle to the recorder, tagged with the shooter.
class AAR_ShotListener
{
	protected AAR_Recorder m_Recorder;
	protected IEntity m_Shooter;
	protected EventHandlerManagerComponent m_Handlers;

	void AAR_ShotListener(AAR_Recorder recorder, IEntity shooter, EventHandlerManagerComponent handlers)
	{
		m_Recorder = recorder;
		m_Shooter = shooter;
		m_Handlers = handlers;
		m_Handlers.RegisterScriptHandler("OnProjectileShot", this, OnProjectileShot);
	}

	void Detach()
	{
		if (m_Handlers)
			m_Handlers.RemoveScriptHandler("OnProjectileShot", this, OnProjectileShot);
		m_Handlers = null;
	}

	protected void OnProjectileShot(int playerID, BaseWeaponComponent weapon, IEntity entity)
	{
		if (m_Recorder && m_Shooter)
			m_Recorder.OnShot(m_Shooter, weapon, entity);
	}
}

//! Where a unit sits in the ORBAT: faction > company > platoon > squad, from the group's callsign.
class AAR_GroupInfo
{
	string m_Faction;
	string m_Company;
	string m_Platoon;
	string m_Squad;
	string m_Name;
	string m_NodeId;
}

class AAR_OrbatNode
{
	string m_Id;
	string m_Name;
	int m_Order;
	ref array<ref AAR_OrbatNode> m_Children = new array<ref AAR_OrbatNode>();

	void AAR_OrbatNode(string id, string name, int order)
	{
		m_Id = id;
		m_Name = name;
		m_Order = order;
	}

	AAR_OrbatNode Child(string id, string name)
	{
		foreach (AAR_OrbatNode c : m_Children)
		{
			if (c.m_Id == id)
				return c;
		}
		AAR_OrbatNode node = new AAR_OrbatNode(id, name, m_Children.Count());
		m_Children.Insert(node);
		return node;
	}

	string Json()
	{
		string children;
		foreach (int i, AAR_OrbatNode c : m_Children)
		{
			if (i > 0)
				children += ",";
			children += c.Json();
		}
		return "{\"id\":" + AAR_Json.Str(m_Id) + ",\"name\":" + AAR_Json.Str(m_Name) + ",\"full_name\":" + AAR_Json.Str(m_Name)
			+ ",\"icon\":\"\",\"modifier\":\"\",\"order\":" + m_Order.ToString() + ",\"children\":[" + children + "]}";
	}
}

//! Records one mission on the server into $profile:aar/<utc>_<mission>_<world>.jsonl.
class AAR_Recorder
{
	static const int VERSION = 1;
	static const int INTERVAL_MS = 1000;
	static const float KEYFRAME_INTERVAL = 60;
	static const float MIN_MOVE = 0.1;
	static const float MIN_TURN = 1;
	static const float MIN_DAMAGE = 0.01;

	protected SCR_BaseGameMode m_GameMode;
	protected SCR_EditableEntityCore m_Core;
	protected ref FileHandle m_File;
	protected ref array<string> m_Lines = new array<string>();
	protected ref array<ref AAR_Tracked> m_Tracked = new array<ref AAR_Tracked>();
	protected ref map<IEntity, int> m_IdByEntity = new map<IEntity, int>();
	protected ref map<int, AAR_Tracked> m_ById = new map<int, AAR_Tracked>();
	protected int m_NextId = 1;
	protected int m_NextShotId = 1;
	protected float m_LastKeyframe = -1000000;
	protected string m_LastOrbat;
	protected bool m_Running;
	protected bool m_Idle;

	void ~AAR_Recorder()
	{
		Stop("shutdown");
	}

	bool Start(SCR_BaseGameMode gameMode)
	{
		m_GameMode = gameMode;

		string world = BaseName(GetGame().GetWorldFile());
		string mission, author, gameType;
		int maxPlayers;
		SCR_MissionHeader header = SCR_MissionHeader.Cast(GetGame().GetMissionHeader());
		if (header)
		{
			mission = header.m_sName;
			author = header.m_sAuthor;
			gameType = header.m_sGameMode;
			maxPlayers = header.m_iPlayerCount;
		}
		if (mission.IsEmpty())
			mission = world;

		int year, month, day, hour, minute, second;
		System.GetYearMonthDayUTC(year, month, day);
		System.GetHourMinuteSecondUTC(hour, minute, second);
		string stamp = year.ToString(4) + month.ToString(2) + day.ToString(2) + "-" + hour.ToString(2) + minute.ToString(2) + second.ToString(2);
		string utc = year.ToString(4) + "-" + month.ToString(2) + "-" + day.ToString(2) + "T" + hour.ToString(2) + ":" + minute.ToString(2) + ":" + second.ToString(2) + "Z";

		FileIO.MakeDirectory("$profile:aar");
		string path = "$profile:aar/" + stamp + "_" + Sanitize(mission) + "_" + Sanitize(world) + ".jsonl";
		m_File = FileIO.OpenFile(path, FileMode.WRITE);
		if (!m_File)
		{
			Print("[AAR] could not open " + path, LogLevel.ERROR);
			return false;
		}
		Print("[AAR] recording to " + path);
		m_Running = true;

		AAR_Line line = new AAR_Line("header", 0);
		line.Int("version", VERSION).Str("game", "reforger").Str("mission", mission).Str("world", world).Str("started_utc", utc);
		line.Num("interval", INTERVAL_MS / 1000.0).Num("keyframe_interval", KEYFRAME_INTERVAL).Bool("multiplayer", RplSession.Mode() != RplMode.None);
		line.Str("author", author).Str("game_type", gameType).Int("max_players", maxPlayers).Str("world_file", GetGame().GetWorldFile());
		line.Str("game_version", GetGame().GetBuildVersion());
		Write(line.Done());

		gameMode.GetOnControllableSpawned().Insert(OnControllableSpawned);
		gameMode.GetOnControllableDestroyed().Insert(OnControllableDestroyed);
		gameMode.GetOnControllableDeleted().Insert(OnControllableDeleted);
		gameMode.GetOnPlayerConnected().Insert(OnPlayerConnected);
		gameMode.GetOnPlayerDisconnected().Insert(OnPlayerDisconnected);
		gameMode.GetOnPlayerSpawned().Insert(OnPlayerSpawned);

		// Every character and vehicle has an editable entity component (that's how Game Master sees them),
		// so the editable entity core is a ready-made registry of everything worth recording.
		m_Core = SCR_EditableEntityCore.Cast(SCR_EditableEntityCore.GetInstance(SCR_EditableEntityCore));
		if (m_Core)
		{
			m_Core.Event_OnEntityRegistered.Insert(OnEditableRegistered);
			set<SCR_EditableEntityComponent> existing = new set<SCR_EditableEntityComponent>();
			m_Core.GetAllEntities(existing);
			foreach (SCR_EditableEntityComponent editable : existing)
				OnEditableRegistered(editable);
		}
		else
		{
			Print("[AAR] no editable entity core; only spawned characters will be recorded", LogLevel.WARNING);
		}

		Tick();
		GetGame().GetCallqueue().CallLater(Tick, INTERVAL_MS, true);
		return true;
	}

	void Stop(string reason)
	{
		if (!m_Running)
			return;
		m_Running = false;

		if (GetGame() && GetGame().GetCallqueue())
			GetGame().GetCallqueue().Remove(Tick);
		if (m_Core)
			m_Core.Event_OnEntityRegistered.Remove(OnEditableRegistered);
		if (m_GameMode)
		{
			m_GameMode.GetOnControllableSpawned().Remove(OnControllableSpawned);
			m_GameMode.GetOnControllableDestroyed().Remove(OnControllableDestroyed);
			m_GameMode.GetOnControllableDeleted().Remove(OnControllableDeleted);
			m_GameMode.GetOnPlayerConnected().Remove(OnPlayerConnected);
			m_GameMode.GetOnPlayerDisconnected().Remove(OnPlayerDisconnected);
			m_GameMode.GetOnPlayerSpawned().Remove(OnPlayerSpawned);
		}
		foreach (AAR_Tracked tr : m_Tracked)
		{
			if (tr.m_Shots)
				tr.m_Shots.Detach();
		}

		AAR_Line line = new AAR_Line("end", Now());
		line.Str("reason", reason).Int("entities", m_NextId - 1);
		Write(line.Done());
		Flush();
		if (m_File)
			m_File.Close();
		m_File = null;
		Print("[AAR] recording stopped: " + reason);
	}

	// --- snapshots -------------------------------------------------------------------------

	protected void Tick()
	{
		if (!m_Running)
			return;
		float t = Now();

		// A dedicated server with nobody on it records nothing until someone joins.
		if (System.IsConsoleApp())
		{
			bool idle = GetGame().GetPlayerManager().GetPlayerCount() == 0;
			if (idle != m_Idle)
			{
				m_Idle = idle;
				AAR_Line idleLine = new AAR_Line("idle", t);
				idleLine.Bool("idle", idle);
				Write(idleLine.Done());
				if (!idle)
					m_LastKeyframe = -1000000;
			}
			if (idle)
			{
				Flush();
				return;
			}
		}

		bool key = t - m_LastKeyframe >= KEYFRAME_INTERVAL;
		if (key)
		{
			m_LastKeyframe = t;
			RefreshGroups(t);
		}

		string entries;
		int count;
		for (int i = m_Tracked.Count() - 1; i >= 0; i--)
		{
			AAR_Tracked tr = m_Tracked[i];
			if (!tr.m_Entity)
			{
				Untrack(tr, t);
				continue;
			}

			vector pos = tr.m_Entity.GetOrigin();
			vector fwd = tr.m_Entity.GetTransformAxis(2);
			float dir = Math.Atan2(fwd[0], fwd[2]) * Math.RAD2DEG;
			if (dir < 0)
				dir += 360;
			bool alive = true;
			float damage = 0;
			if (tr.m_Damage)
			{
				alive = !tr.m_Damage.IsDestroyed();
				damage = 1 - tr.m_Damage.GetHealthScaled();
			}
			int vehicle = 0;
			if (tr.m_IsUnit)
			{
				IEntity veh = CompartmentAccessComponent.GetVehicleIn(tr.m_Entity);
				if (veh && veh != tr.m_Entity)
					vehicle = Track(veh);
			}

			float turn = Math.AbsFloat(dir - tr.m_Dir);
			if (turn > 180)
				turn = 360 - turn;
			bool changed = key || !tr.m_Sent || vector.Distance(pos, tr.m_Pos) > MIN_MOVE || turn > MIN_TURN
				|| alive != tr.m_Alive || Math.AbsFloat(damage - tr.m_DamageValue) >= MIN_DAMAGE || vehicle != tr.m_Vehicle;
			if (!changed)
				continue;

			tr.m_Sent = true;
			tr.m_Pos = pos;
			tr.m_Dir = dir;
			tr.m_Alive = alive;
			tr.m_DamageValue = damage;
			tr.m_Vehicle = vehicle;

			if (count > 0)
				entries += ",";
			entries += "[" + tr.m_Id.ToString() + "," + AAR_Json.Num(pos[0]) + "," + AAR_Json.Num(pos[2]) + "," + AAR_Json.Num(pos[1]) + ","
				+ AAR_Json.Num(dir, 0) + "," + AAR_Json.Bool(alive) + "," + AAR_Json.Num(damage) + "," + vehicle.ToString() + "]";
			count++;
		}

		if (key || count > 0)
		{
			AAR_Line snap = new AAR_Line("snap", t);
			snap.Bool("key", key).Raw("e", "[" + entries + "]");
			Write(snap.Done());
		}
		Flush();
	}

	//! On each keyframe: write `group` for units that changed group, and `orbat` when the tree changed.
	protected void RefreshGroups(float t)
	{
		map<string, ref AAR_OrbatNode> roots = new map<string, ref AAR_OrbatNode>();
		array<string> factions = new array<string>();

		foreach (AAR_Tracked tr : m_Tracked)
		{
			if (!tr.m_IsUnit || !tr.m_Entity)
				continue;
			AAR_GroupInfo info = GroupInfo(tr.m_Entity);
			if (info.m_NodeId != tr.m_Orbat)
			{
				tr.m_Orbat = info.m_NodeId;
				AAR_Line line = new AAR_Line("group", t);
				line.Int("unit", tr.m_Id).Str("group", info.m_Name).Str("side", FactionKey(tr.m_Entity)).Str("orbat", info.m_NodeId);
				Write(line.Done());
			}
			if (info.m_Faction.IsEmpty() || info.m_NodeId.IsEmpty())
				continue;

			AAR_OrbatNode root;
			if (!roots.Find(info.m_Faction, root))
			{
				root = new AAR_OrbatNode(info.m_Faction, info.m_Faction, factions.Count());
				roots.Insert(info.m_Faction, root);
				factions.Insert(info.m_Faction);
			}
			if (info.m_Company.IsEmpty())
			{
				root.Child(info.m_NodeId, info.m_Name);
				continue;
			}
			string companyId = info.m_Faction + "/" + info.m_Company;
			string platoonId = companyId + "/" + info.m_Platoon;
			AAR_OrbatNode company = root.Child(companyId, info.m_Company);
			AAR_OrbatNode platoon = company.Child(platoonId, info.m_Company + " " + info.m_Platoon);
			platoon.Child(info.m_NodeId, info.m_Name);
		}

		string teams;
		foreach (int i, string faction : factions)
		{
			if (i > 0)
				teams += ",";
			teams += "{\"side\":" + AAR_Json.Str(faction) + ",\"faction\":" + AAR_Json.Str(faction) + ",\"root\":" + roots.Get(faction).Json() + "}";
		}
		if (teams.IsEmpty() || teams == m_LastOrbat)
			return;
		m_LastOrbat = teams;
		AAR_Line orbat = new AAR_Line("orbat", t);
		orbat.Str("source", "reforger").Raw("teams", "[" + teams + "]");
		Write(orbat.Done());
	}

	// --- entities ---------------------------------------------------------------------------

	//! Id of a unit or vehicle, recording it first if needed. 0 for anything else.
	int Track(IEntity ent)
	{
		if (!ent)
			return 0;
		int id;
		if (m_IdByEntity.Find(ent, id))
			return id;

		bool isUnit = ChimeraCharacter.Cast(ent) != null;
		if (!isUnit && !Vehicle.Cast(ent))
			return 0;

		id = m_NextId;
		m_NextId++;
		AAR_Tracked tr = new AAR_Tracked();
		tr.m_Entity = ent;
		tr.m_Id = id;
		tr.m_IsUnit = isUnit;
		tr.m_Damage = DamageManagerComponent.Cast(ent.FindComponent(DamageManagerComponent));
		m_Tracked.Insert(tr);
		m_IdByEntity.Insert(ent, id);
		m_ById.Insert(id, tr);

		string prefab = PrefabName(ent);
		AAR_Line line = new AAR_Line("entity", Now());
		line.Int("id", id).Str("kind", Kind(ent, prefab, isUnit)).Str("class", prefab).Str("display", Display(prefab)).Str("side", FactionKey(ent));
		if (isUnit)
		{
			int playerId = GetGame().GetPlayerManager().GetPlayerIdFromControlledEntity(ent);
			AAR_GroupInfo info = GroupInfo(ent);
			tr.m_Orbat = info.m_NodeId;
			line.Str("name", PlayerName(playerId)).Str("group", info.m_Name).Bool("player", playerId > 0).Str("uid", PlayerUid(playerId));
			if (!info.m_NodeId.IsEmpty())
				line.Str("orbat", info.m_NodeId);
		}
		Write(line.Done());

		EventHandlerManagerComponent handlers = EventHandlerManagerComponent.Cast(ent.FindComponent(EventHandlerManagerComponent));
		if (handlers)
			tr.m_Shots = new AAR_ShotListener(this, ent, handlers);
		return id;
	}

	protected void Untrack(AAR_Tracked tr, float t)
	{
		AAR_Line line = new AAR_Line("deleted", t);
		line.Int("id", tr.m_Id);
		Write(line.Done());
		if (tr.m_Shots)
			tr.m_Shots.Detach();
		if (tr.m_Entity)
			m_IdByEntity.Remove(tr.m_Entity);
		m_ById.Remove(tr.m_Id);
		m_Tracked.RemoveItem(tr);
	}

	// --- events -----------------------------------------------------------------------------

	protected void OnEditableRegistered(SCR_EditableEntityComponent editable)
	{
		if (m_Running && editable)
			Track(editable.GetOwner());
	}

	protected void OnControllableSpawned(IEntity entity)
	{
		if (m_Running)
			Track(entity);
	}

	protected void OnControllableDeleted(IEntity entity)
	{
		int id;
		if (!m_Running || !entity || !m_IdByEntity.Find(entity, id))
			return;
		AAR_Tracked tr = m_ById.Get(id);
		if (tr)
			Untrack(tr, Now());
	}

	protected void OnControllableDestroyed(notnull SCR_InstigatorContextData data)
	{
		if (!m_Running)
			return;
		IEntity victim = data.GetVictimEntity();
		int victimId = Track(victim);
		if (victimId == 0)
			return;
		int instigatorId = 0;
		Instigator instigator = data.GetInstigator();
		if (instigator)
			instigatorId = Track(instigator.GetInstigatorEntity());

		AAR_Line line = new AAR_Line("killed", Now());
		line.Int("victim", victimId).Int("killer", Track(data.GetKillerEntity())).Int("instigator", instigatorId).Pos("pos", victim.GetOrigin());
		Write(line.Done());
	}

	protected void OnPlayerSpawned(int playerId, IEntity player)
	{
		if (!m_Running)
			return;
		int unit = Track(player);
		if (unit == 0)
			return;
		AAR_Line line = new AAR_Line("player", Now());
		line.Int("unit", unit).Str("uid", PlayerUid(playerId)).Str("name", PlayerName(playerId));
		Write(line.Done());
	}

	protected void OnPlayerConnected(int playerId)
	{
		if (!m_Running)
			return;
		AAR_Line line = new AAR_Line("connected", Now());
		line.Str("uid", PlayerUid(playerId)).Str("name", PlayerName(playerId)).Int("owner", playerId);
		Write(line.Done());
	}

	protected void OnPlayerDisconnected(int playerId, KickCauseCode cause, int timeout)
	{
		if (!m_Running)
			return;
		AAR_Line line = new AAR_Line("disconnected", Now());
		line.Str("uid", PlayerUid(playerId)).Str("name", PlayerName(playerId)).Int("owner", playerId);
		Write(line.Done());
	}

	//! Called by AAR_ShotListener. Experimental: proves whether shots reach the server at all.
	void OnShot(IEntity shooter, BaseWeaponComponent weapon, IEntity entity)
	{
		if (!m_Running)
			return;
		int shooterId = Track(shooter);
		if (shooterId == 0)
			return;
		string weaponName;
		if (weapon)
			weaponName = PrefabName(weapon.GetOwner());
		string ammo;
		vector pos = shooter.GetOrigin();
		if (entity && entity != shooter && !ChimeraCharacter.Cast(entity))
		{
			ammo = PrefabName(entity);
			pos = entity.GetOrigin();
		}

		AAR_Line line = new AAR_Line("shot", Now());
		line.Int("id", m_NextShotId).Int("shooter", shooterId).Str("weapon", weaponName).Str("ammo", ammo).Pos("pos", pos);
		m_NextShotId++;
		Write(line.Done());
	}

	// --- helpers ----------------------------------------------------------------------------

	protected void Write(string line)
	{
		m_Lines.Insert(line);
	}

	protected void Flush()
	{
		if (!m_File)
			return;
		foreach (string line : m_Lines)
			m_File.WriteLine(line);
		m_Lines.Clear();
	}

	protected float Now()
	{
		if (!GetGame() || !GetGame().GetWorld())
			return 0;
		return GetGame().GetWorld().GetWorldTime() / 1000.0;
	}

	protected AAR_GroupInfo GroupInfo(IEntity ent)
	{
		AAR_GroupInfo info = new AAR_GroupInfo();
		int playerId = GetGame().GetPlayerManager().GetPlayerIdFromControlledEntity(ent);
		SCR_AIGroup group;
		if (playerId > 0)
		{
			SCR_GroupsManagerComponent groups = SCR_GroupsManagerComponent.GetInstance();
			if (groups)
				group = groups.GetPlayerGroup(playerId);
		}
		if (!group)
		{
			AIControlComponent control = AIControlComponent.Cast(ent.FindComponent(AIControlComponent));
			if (control && control.GetControlAIAgent())
				group = SCR_AIGroup.Cast(control.GetControlAIAgent().GetParentGroup());
		}
		if (!group)
			return info;

		Faction faction = group.GetFaction();
		if (faction)
			info.m_Faction = faction.GetFactionKey();
		else
			info.m_Faction = FactionKey(ent);

		string company, platoon, squad, character, format;
		group.GetCallsigns(company, platoon, squad, character, format);
		info.m_Company = Unlocalize(company);
		info.m_Platoon = Unlocalize(platoon);
		info.m_Squad = Unlocalize(squad);

		string custom = group.GetCustomName();
		if (!info.m_Company.IsEmpty())
		{
			info.m_NodeId = info.m_Faction + "/" + info.m_Company + "/" + info.m_Platoon + "/" + info.m_Squad;
			info.m_Name = info.m_Company + " " + info.m_Platoon + "-" + info.m_Squad;
			if (!custom.IsEmpty())
				info.m_Name = custom + " (" + info.m_Name + ")";
		}
		else
		{
			info.m_NodeId = info.m_Faction + "/group" + group.GetGroupID().ToString();
			info.m_Name = custom;
			if (info.m_Name.IsEmpty())
				info.m_Name = "Group " + group.GetGroupID().ToString();
		}
		return info;
	}

	protected static string FactionKey(IEntity ent)
	{
		FactionAffiliationComponent affiliation = FactionAffiliationComponent.Cast(ent.FindComponent(FactionAffiliationComponent));
		if (!affiliation)
			return "";
		Faction faction = affiliation.GetAffiliatedFaction();
		if (!faction)
			return "";
		return faction.GetFactionKey();
	}

	protected static string PlayerName(int playerId)
	{
		if (playerId <= 0)
			return "";
		return GetGame().GetPlayerManager().GetPlayerName(playerId);
	}

	protected static string PlayerUid(int playerId)
	{
		if (playerId <= 0 || !GetGame().GetBackendApi())
			return "";
		return GetGame().GetBackendApi().GetPlayerIdentityId(playerId);
	}

	protected static string PrefabName(IEntity ent)
	{
		if (!ent || !ent.GetPrefabData())
			return "";
		return ent.GetPrefabData().GetPrefabName();
	}

	//! Vanilla prefabs live under Prefabs/Vehicles/<Wheeled|Tracked|Helicopters|Boats>/...
	protected static string Kind(IEntity ent, string prefab, bool isUnit)
	{
		if (isUnit)
			return "unit";
		string p = prefab;
		p.ToLower();
		if (p.Contains("helicopter"))
			return "heli";
		if (p.Contains("plane") || p.Contains("aircraft"))
			return "plane";
		if (p.Contains("boat") || p.Contains("ship"))
			return "ship";
		if (p.Contains("tracked") || p.Contains("tank"))
			return "tank";
		if (p.Contains("static") || p.Contains("turret") || p.Contains("tripod"))
			return "static";
		return "car";
	}

	//! "{GUID}Prefabs/Characters/Factions/BLUFOR/US_Army/Character_US_Rifleman.et" -> "Character_US_Rifleman"
	protected static string Display(string prefab)
	{
		string name = BaseName(prefab);
		int dot = name.LastIndexOf(".");
		if (dot > 0)
			name = name.Substring(0, dot);
		return name;
	}

	protected static string BaseName(string path)
	{
		int slash = path.LastIndexOf("/");
		if (slash >= 0)
			return path.Substring(slash + 1, path.Length() - slash - 1);
		return path;
	}

	//! Callsign parts are string table keys like "#AR-Callsign_Alpha"; keep the readable tail.
	protected static string Unlocalize(string key)
	{
		if (!key.StartsWith("#"))
			return key;
		int underscore = key.LastIndexOf("_");
		if (underscore >= 0)
			return key.Substring(underscore + 1, key.Length() - underscore - 1);
		return key.Substring(1, key.Length() - 1);
	}

	protected static string Sanitize(string s)
	{
		string allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";
		string r;
		for (int i = 0; i < s.Length(); i++)
		{
			string c = s.Substring(i, 1);
			if (allowed.Contains(c))
				r += c;
			else
				r += "_";
		}
		if (r.IsEmpty())
			return "mission";
		return r;
	}
}
