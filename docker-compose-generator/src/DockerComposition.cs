﻿using System;
using System.Linq;
using System.Collections.Generic;
using System.Text;

namespace DockerGenerator
{
	public class DockerComposition
	{
		public string WithFullNode
		{
			get;
			set;
		}
		public string SelectedProxy
		{
			get;
			set;
		}
		public string SelectedLN
		{
			get;
			set;
		}
		public string[] AdditionalFragments
		{
			get;
			set;
		} = new string[0];
		public string[] ExcludeFragments
		{
			get;
			set;
		} = new string[0];

		public static DockerComposition FromEnvironmentVariables()
		{
			DockerComposition composition = new DockerComposition();
			composition.WithFullNode = (Environment.GetEnvironmentVariable("AMBOSS_FULLNODE") ?? "").ToLowerInvariant();
			composition.SelectedProxy = (Environment.GetEnvironmentVariable("AMBOSSGEN_REVERSEPROXY") ?? "").ToLowerInvariant();
			composition.SelectedLN = (Environment.GetEnvironmentVariable("AMBOSSGEN_LIGHTNING") ?? "").ToLowerInvariant();
			composition.AdditionalFragments = (Environment.GetEnvironmentVariable("AMBOSSGEN_ADDITIONAL_FRAGMENTS") ?? "").ToLowerInvariant()
												.Split(new char[] { ';' , ',' })
												.Where(t => !string.IsNullOrWhiteSpace(t))
												.Select(t => t.EndsWith(".yml") ? t.Substring(0, t.Length - ".yml".Length) : t)
												.ToArray();
			composition.ExcludeFragments = (Environment.GetEnvironmentVariable("AMBOSSGEN_EXCLUDE_FRAGMENTS") ?? "").ToLowerInvariant()
												.Split(new char[] { ';' , ',' })
												.Where(t => !string.IsNullOrWhiteSpace(t))
												.Select(t => t.EndsWith(".yml") ? t.Substring(0, t.Length - ".yml".Length) : t)
												.ToArray();
			return composition;
		}
	}
}
