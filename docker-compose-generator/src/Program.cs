using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using YamlDotNet.Serialization;

namespace DockerGenerator
{
	class Program
	{

		static void Main(string[] args)
		{
			var root = Environment.GetEnvironmentVariable("INSIDE_CONTAINER") == "1" ? FindRoot("app")
				: Path.GetFullPath(Path.Combine(FindRoot("docker-compose-generator"), ".."));

			var composition = DockerComposition.FromEnvironmentVariables();
			
			Console.WriteLine("ReverseProxy: " + composition.SelectedProxy);
			var generatedLocation = Path.GetFullPath(Path.Combine(root, "Generated"));

			var name = Environment.GetEnvironmentVariable("AMBOSSGEN_SUBNAME");
			name = string.IsNullOrEmpty(name) ? "generated" : name;
			try
			{
				new Program().Run(composition, name, generatedLocation);
			}
			catch (YamlBuildException ex)
			{
				ConsoleUtils.WriteLine(ex.Message, ConsoleColor.Red);
				Environment.ExitCode = 1;
			}
		}

		private void Run(DockerComposition composition, string name, string output)
		{
			var root = Environment.GetEnvironmentVariable("INSIDE_CONTAINER") == "1" ? "app" : "docker-compose-generator";
			 root = FindRoot(root);
			var fragmentLocation = Path.GetFullPath(Path.Combine(root, "docker-fragments"));
			var fragments = new HashSet<string>();
			switch (composition.SelectedProxy)
			{
				case "nginx":
					fragments.Add("nginx");
					break;
				default:
					fragments.Add("amboss-no-nginx");
					break;
			}
			fragments.Add("amboss");

			Environment.SetEnvironmentVariable("BTCPAY_BUILD_CONFIGURATION", "");

			foreach (var fragment in composition.AdditionalFragments)
			{
				fragments.Add(fragment);
			}
			var def = new DockerComposeDefinition(name, fragments.Select(f => new FragmentName(f)).ToHashSet())
			{
				ExcludeFragments = composition.ExcludeFragments.Select(f => new FragmentName(f)).ToHashSet()
			};
			def.FragmentLocation = fragmentLocation;
			def.BuildOutputDirectory = output;
			def.Build();
		}

		private static string FindRoot(string rootDirectory)
		{
			string directory = Directory.GetCurrentDirectory();
			int i = 0;
			while (true)
			{
				if (i > 10)
					throw new DirectoryNotFoundException(rootDirectory);
				if (directory.EndsWith(rootDirectory))
					return directory;
				directory = Path.GetFullPath(Path.Combine(directory, ".."));
				i++;
			}
		}
	}
}
