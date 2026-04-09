// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

using System.Buffers;
using System.Diagnostics;
using System.Formats.Tar;
using System.IO.Compression;
using System.Net;

// Constants
const string DefaultVersion = "5.4.8";
const string LuaBaseUrl = "https://www.lua.org/ftp/";

// Parse command-line arguments manually
var version = DefaultVersion;
var force = false;
var premakeDir = Directory.GetCurrentDirectory();
var remainingArgs = new List<string>();
//Console.WriteLine(string.Join(" ", Environment.GetCommandLineArgs()));
for (var i = 0; i < args.Length; ++i)
{
	switch (args[i])
	{
		case "--version":
			if (i + 1 < args.Length)
			{
				version = args[++i];
			}
			break;
		case "--force":
			force = true;
			break;
		case "--premake-dir":
			if (i + 1 < args.Length)
			{
				premakeDir = args[++i];
			}
			break;
		default:
			remainingArgs.Add(args[i]);
			break;
	}
}
args = remainingArgs.ToArray();

// Main execution
try
{
	await DownloadLuaAsync(version, force, args, premakeDir);
}
catch (Exception ex)
{
	Console.Error.WriteLine($"Error: {ex.Message}");
	return 1;
}

return 0;

// Main function
static async Task DownloadLuaAsync(string version, bool force, string[] remainingArgs, string premakeDir)
{
	var filename = $"lua-{version}.tar.gz";
	var downloadUrl = $"{LuaBaseUrl}{filename}";

	// Get script directory (the .cmd file changes to this directory with cd /d "%~dp0")
	var scriptDir = Directory.GetCurrentDirectory();
	var versionedLuaDir = Path.Combine(scriptDir, $"lua-{version}");
	var srcDir = Path.Combine(versionedLuaDir, "src");
	var downloadPath = Path.Combine(scriptDir, filename);

	Console.WriteLine($"Lua version  : {version}");
	Console.WriteLine($"Download URL : {downloadUrl}");
	Console.WriteLine($"Download path: {downloadPath}");
	Console.WriteLine();

	// Check if Lua source already exists
	if (Directory.Exists(srcDir))
	{
		if (force)
		{
			Console.WriteLine("Force flag specified. Removing existing Lua source...");
			Directory.Delete(srcDir, true);
		}
		else
		{
			Console.WriteLine($"Lua source already exists at: {srcDir}");
			Console.WriteLine("Skipping download. Use --force to redownload.");
			return;
		}
	}

	// Create directory
	Directory.CreateDirectory(versionedLuaDir);

	// Download file
	await DownloadFileAsync(downloadUrl, downloadPath);

	// Extract tar.gz directly to versioned directory
	ExtractTarGz(downloadPath, scriptDir, version);

	// Delete the downloaded tar.gz file
	File.Delete(downloadPath);

	Console.WriteLine("Done!");

	// Run premake5.exe
	await RunPremakeAsync(premakeDir, version, remainingArgs);
}

static async Task DownloadFileAsync(string url, string outputPath)
{
	Console.WriteLine("Downloading Lua...");

	using var httpClient = new HttpClient();
	httpClient.BaseAddress = null;
	httpClient.DefaultRequestVersion = HttpVersion.Version30;
	httpClient.DefaultVersionPolicy = HttpVersionPolicy.RequestVersionOrLower;
	httpClient.Timeout = TimeSpan.FromSeconds(30);

	try
	{
		var response = await httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
		response.EnsureSuccessStatusCode();

		var totalBytes = response.Content.Headers.ContentLength ?? 0;
		var bytesRead = 0L;

		await using var fileStream = new FileStream(outputPath, FileMode.Create, FileAccess.Write);
		await using var contentStream = await response.Content.ReadAsStreamAsync();

		var buffer = ArrayPool<byte>.Shared.Rent(81_920); // 80KB buffer
		try
		{
			int count;
			while ((count = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
			{
				await fileStream.WriteAsync(buffer, 0, count);
				bytesRead += count;

				if (totalBytes > 0)
				{
					var progress = Math.Round((bytesRead / (double)totalBytes) * 100, 2);
					Console.Write($"\rDownloading Lua... {progress:F2}% Complete");
				}
			}

			Console.WriteLine();
			Console.WriteLine("Download completed successfully.");
		}
		finally
		{
			ArrayPool<byte>.Shared.Return(buffer);
		}
	}
	catch (Exception ex)
	{
		Console.Error.WriteLine($"Download failed: {ex.Message}");
		throw;
	}
}

static void ExtractTarGz(string gzPath, string scriptDir, string version)
{
	Console.WriteLine("Extracting files...");

	var tarPath = Path.Combine(scriptDir, $"lua-{version}.tar");

	// Decompress .tar.gz to .tar
	DecompressGzip(gzPath, tarPath);

	// Extract tar file filtering .c, .h, and .hpp files
	ExtractTarFiltered(tarPath, scriptDir);

	// Delete the intermediate .tar file
	File.Delete(tarPath);

	Console.WriteLine("Extraction completed.");
}

static void DecompressGzip(string gzipPath, string outputPath)
{
	using var inputFile = new FileInfo(gzipPath).OpenRead();
	using var outputFile = new FileInfo(outputPath).Create();
	using var gzipStream = new GZipStream(inputFile, CompressionMode.Decompress);
	gzipStream.CopyTo(outputFile);
}

static void ExtractTarFiltered(string tarPath, string tempDir)
{
	using var fileStream = new FileInfo(tarPath).OpenRead();
	using var tarReader = new TarReader(fileStream);

	var filesExtracted = 0;
	var allowedExtensions = new[] { ".c", ".h", ".hpp" };

	while (tarReader.GetNextEntry() is { } entry)
	{
		if (entry.EntryType == TarEntryType.RegularFile)
		{
			var extension = Path.GetExtension(entry.Name);
			if (Array.Exists(allowedExtensions, e => e == extension))
			{
				var destPath = Path.Combine(tempDir, entry.Name);
				var destDir = Path.GetDirectoryName(destPath);

				if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
				{
					Directory.CreateDirectory(destDir);
				}

				entry.ExtractToFile(destPath, overwrite: true);
				filesExtracted++;
			}
		}
	}

	Console.WriteLine($"Extracted {filesExtracted} files.");
}

static async Task RunPremakeAsync(string premakeDir, string version, string[] remainingArgs)
{
	var processStartInfo = new ProcessStartInfo
	{
		FileName = "premake5",
		UseShellExecute = false,
		CreateNoWindow = true,
		RedirectStandardOutput = true,
		RedirectStandardError = true,
		WorkingDirectory = premakeDir,
		//WindowStyle = ProcessWindowStyle.Hidden
	};

	processStartInfo.ArgumentList.Add("--arch=x86_64");
	processStartInfo.ArgumentList.Add("--os=windows");
	processStartInfo.ArgumentList.Add("--shell=cmd");
	processStartInfo.ArgumentList.Add("--verbose");
	processStartInfo.ArgumentList.Add("--cc=msc-v145"); // VS2026
	processStartInfo.ArgumentList.Add("--dotnet=msnet");
	processStartInfo.ArgumentList.Add("vs2026");
	processStartInfo.ArgumentList.Add($"--lua=lua-{version}");

	foreach (var arg in remainingArgs)
	{
		processStartInfo.ArgumentList.Add(arg);
	}

	var premakeArgs = string.Join(" ", processStartInfo.ArgumentList);
	Console.WriteLine($"Running: premake5 {premakeArgs}");

	try
	{
		using var process = Process.Start(processStartInfo);
		if (process != null)
		{
			await process.WaitForExitAsync();
		}
	}
	catch (Exception ex)
	{
		Console.Error.WriteLine($"Failed to run premake5.exe: {ex.Message}");
		throw;
	}
}
