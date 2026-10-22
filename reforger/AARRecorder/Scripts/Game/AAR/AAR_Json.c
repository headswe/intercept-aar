//! Helpers that build one .jsonl record at a time, in the same format as the Arma 3 recorder.
class AAR_Json
{
	static string Str(string s)
	{
		string r = s;
		r.Replace("\\", "\\\\");
		r.Replace("\"", "\\\"");
		r.Replace("\n", "\\n");
		r.Replace("\t", "\\t");
		return "\"" + r + "\"";
	}

	//! Number with at most `dec` decimals, trailing zeros trimmed.
	static string Num(float v, int dec = 2)
	{
		string s = v.ToString(-1, dec);
		if (s.Contains("."))
		{
			int len = s.Length();
			while (len > 0 && s.Substring(len - 1, 1) == "0")
				len--;
			if (len > 0 && s.Substring(len - 1, 1) == ".")
				len--;
			s = s.Substring(0, len);
		}
		if (s == "-0" || s.IsEmpty())
			return "0";
		return s;
	}

	static string Bool(bool b)
	{
		if (b)
			return "true";
		return "false";
	}

	//! Enfusion vectors are [x, up, z]; the recording uses [x, y, z] with z up, like Arma 3.
	static string Pos(vector p)
	{
		return "[" + Num(p[0]) + "," + Num(p[2]) + "," + Num(p[1]) + "]";
	}
}

//! One record: `new AAR_Line("killed", t)`, add fields, then `Done()`.
class AAR_Line
{
	protected string m_Text;

	void AAR_Line(string type, float t)
	{
		m_Text = "{\"type\":" + AAR_Json.Str(type) + ",\"t\":" + AAR_Json.Num(t);
	}

	AAR_Line Str(string key, string value)
	{
		m_Text += ",\"" + key + "\":" + AAR_Json.Str(value);
		return this;
	}

	AAR_Line Int(string key, int value)
	{
		m_Text += ",\"" + key + "\":" + value.ToString();
		return this;
	}

	AAR_Line Num(string key, float value, int dec = 2)
	{
		m_Text += ",\"" + key + "\":" + AAR_Json.Num(value, dec);
		return this;
	}

	AAR_Line Bool(string key, bool value)
	{
		m_Text += ",\"" + key + "\":" + AAR_Json.Bool(value);
		return this;
	}

	AAR_Line Pos(string key, vector value)
	{
		m_Text += ",\"" + key + "\":" + AAR_Json.Pos(value);
		return this;
	}

	//! Already-encoded JSON value (array or object).
	AAR_Line Raw(string key, string json)
	{
		m_Text += ",\"" + key + "\":" + json;
		return this;
	}

	string Done()
	{
		return m_Text + "}";
	}
}
