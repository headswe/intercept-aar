//! Starts the recorder with every scenario, on the server only. No scenario or prefab changes needed.
modded class SCR_BaseGameMode
{
	protected ref AAR_Recorder m_AAR_Recorder;

	protected override void OnGameStart()
	{
		super.OnGameStart();
		if (!Replication.IsServer() || m_AAR_Recorder)
			return;
		m_AAR_Recorder = new AAR_Recorder();
		if (!m_AAR_Recorder.Start(this))
			m_AAR_Recorder = null;
	}

	override void OnGameEnd()
	{
		if (m_AAR_Recorder)
		{
			m_AAR_Recorder.Stop("game_end");
			m_AAR_Recorder = null;
		}
		super.OnGameEnd();
	}
}
