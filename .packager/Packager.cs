// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

const string ApiUrl = "https://api.nanos-world.com";
const string PackageToml = "Package.toml";
//const string UserAgent = "Cheatoid.NanosWorldPackager/v{0}"; // {0} is replaced with app version
const string UserAgent =
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36";

c.OutputEncoding = Encoding.UTF8;
//c.Clear();
c.Title = $"nanos world packager (v{ToolVersion}) by Cheatoid";

// HTTP client setup boilerplate
// @formatter:off
var cookies = new CookieContainer(); // Container for HTTP cookies
using var http_handler = new SocketsHttpHandler(); // HTTP handler using sockets
http_handler.AllowAutoRedirect           = true;                           // Automatically follow HTTP redirects
http_handler.ConnectTimeout              = TimeSpan.FromSeconds(60);       // Connection timeout: 60 seconds
http_handler.MaxAutomaticRedirections    = 10;                             // Max redirects: 10
http_handler.MaxConnectionsPerServer     = 10;                             // Max connections per server: 10
http_handler.PooledConnectionIdleTimeout = TimeSpan.FromMinutes(5);        // Idle connection timeout: 5 minutes
http_handler.PooledConnectionLifetime    = TimeSpan.FromMinutes(10);       // Connection lifetime: 10 minutes
http_handler.AutomaticDecompression      = DecompressionMethods.All;       // Auto-decompress all formats (gzip, deflate, brotli)
http_handler.Expect100ContinueTimeout    = TimeSpan.FromSeconds(10);       // Expect-100-continue timeout: 10 seconds
http_handler.ResponseDrainTimeout        = TimeSpan.FromSeconds(5);        // Response drain timeout: 5 seconds
http_handler.KeepAlivePingPolicy         = HttpKeepAlivePingPolicy.Always; // Keep-alive ping: always
http_handler.KeepAlivePingTimeout        = TimeSpan.FromSeconds(20);       // Keep-alive ping timeout: 20 seconds
http_handler.KeepAlivePingDelay          = TimeSpan.FromSeconds(60);       // Keep-alive ping delay: 60 seconds
http_handler.PreAuthenticate             = false;                          // Pre-authenticate: disabled
http_handler.CookieContainer             = cookies;                        // Set cookie container
http_handler.UseCookies                  = false;                          // i luv cookies, but not for this
http_handler.UseProxy                    = false;                          // Proxy: disabled
http_handler.Proxy                       = null;                           // No proxy configured
http_handler.SslOptions = new SslClientAuthenticationOptions               // SSL options configuration
{
	EnabledSslProtocols = System.Security.Authentication.SslProtocols.Tls13, // Use TLS 1.3
};
http_handler.SslOptions = null;                       // nanos still on TLS 1.1
using var http = new HttpClient(http_handler);        // Create HTTP client with handler
http.BaseAddress = new Uri(ApiUrl, UriKind.Absolute); // Set base API URL
http.Timeout = http_handler.ConnectTimeout;           // Set timeout from handler
#pragma warning disable CA2241
http.DefaultRequestHeaders.UserAgent.ParseAdd(string.Format(UserAgent, ToolVersion)); // Set user agent header
#pragma warning restore CA2241
var jsonMediaType = new MediaTypeWithQualityHeaderValue(MediaTypeNames.Application.Json);
http.DefaultRequestHeaders.Accept.Add(jsonMediaType);    // Accept JSON responses
http.DefaultRequestHeaders.Host = http.BaseAddress.Host; // Set Host header
http.DefaultRequestHeaders.Add("Origin", ApiUrl);        // Add Origin header
http.DefaultRequestHeaders.Referrer = http.BaseAddress;  // Set Referrer header
http.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue // Cache control settings
{
	NoCache = true,              // No caching
	NoStore = true,              // Do not store responses
	NoTransform = true,          // Do not transform
	MaxAge = http.Timeout,       // Max age
	MustRevalidate = true,       // Must revalidate
	ProxyRevalidate = true,      // Proxy must revalidate
	SharedMaxAge = http.Timeout, // Shared max age
};
http.DefaultRequestHeaders.Pragma.Add(new NameValueHeaderValue("no-cache")); // Add Pragma: no-cache
//http.DefaultRequestHeaders.IfModifiedSince = DateTime.UtcNow; // nah
// @formatter:on

var token = Environment.GetEnvironmentVariable("NANOS_PERSONAL_ACCESS_TOKEN");
if (string.IsNullOrEmpty(token))
{
	token = Environment.GetEnvironmentVariable("NANOS_API_KEY");
	if (string.IsNullOrEmpty(token))
	{
		token = Environment.GetEnvironmentVariable("NANOS_STORE_TOKEN");
	}
}

var serverFileName = OperatingSystem.IsWindows() ? "NanosWorldServer.exe" : "NanosWorldServer.sh";
string? cliMode = null; // directory to NanosWorldServer
var isReleaseMode = false;
var isUploadPackagesMode = false;
string? singlePackage = null;

// Parse arguments
string[]? dirs;
if (args is { Length: > 0 })
{
	var tmp = new List<string>(args.Length);
	for (var index = 0; index < args.Length; ++index)
	{
		var arg = args[index];
		if (arg is "--")
		{
			// Append remaining args after "--" to tmp
			for (var i = index + 1; i < args.Length; ++i)
			{
				tmp.Add(args[i]);
			}
			// ReSharper disable once RedundantAssignment
			args = tmp.ToArray(); // for convenience (might be used in future)
			// Stop processing args
			break;
		}
		var argLower = arg.ToLowerInvariant();
		if (argLower is "--cli" && index + 1 < args.Length)
		{
			cliMode = args[++index].TrimEnd('\\', '/');
			if (!Path.IsPathFullyQualified(cliMode))
			{
				cliMode = Path.GetFullPath(cliMode,
					Path.GetDirectoryName(Environment.ProcessPath) ?? Environment.CurrentDirectory);
			}
		}
		else if (argLower is "--release" or "-r")
		{
			isReleaseMode = true;
		}
		else if (argLower is "--upload-packages")
		{
			isUploadPackagesMode = true;
		}
		else if (argLower is "--single-package" && index + 1 < args.Length)
		{
			singlePackage = args[++index];
		}
		else if (argLower is "--token" && index + 1 < args.Length)
		{
			token = args[++index];
		}
		else
		{
			tmp.Add(args[index]);
		}
	}
	dirs = tmp.ToArray();
}
else
{
	dirs = null;
}
if (dirs is null || dirs.Length == 0)
{
	dirs = [Path.GetDirectoryName(Environment.ProcessPath) ?? Environment.CurrentDirectory];
}

if (isReleaseMode || isUploadPackagesMode)
{
	if (token is null || (token = token.Trim()).Length == 0)
	{
		//throw new Exception(
		//	"NANOS_PERSONAL_ACCESS_TOKEN / NANOS_API_KEY / NANOS_STORE_TOKEN environment variable is not set");
		c.Error.WriteLine(
			"❗ error: token is required for release/upload-packages mode. Use --token or set environment variable.");
		return 1;
	}
}

foreach (var dir in dirs)
{
	//c.WriteLine(dir);
	var gitRoot = FindGitRoot(dir);
	if (gitRoot == null || !Repository.IsValid(gitRoot))
		continue;

	c.WriteLine($"ℹ found valid git repository > {gitRoot}");
	Directory.SetCurrentDirectory(gitRoot);
	var paths = GetPathsNotIgnored(gitRoot);
	c.WriteLine($"ℹ found {paths.Count} files");
	if (paths.Count <= 0) continue;
	var publishFolder = Path.Combine(gitRoot, "publish");
	Directory.CreateDirectory(publishFolder);

	HashSet<string> directories = [];
	HashSet<string> files = []; // non-binary files only
	foreach (var path in paths)
	{
		c.ForegroundColor = ConsoleColor.White;
		c.WriteLine($"ℹ path: {path}");

		var fileInfo = new FileInfo(path);
		if (fileInfo.Exists)
		{
			if (fileInfo.Attributes.HasFlag(FileAttributes.Directory))
			{
				directories.Add(fileInfo.FullName);
				c.ForegroundColor = ConsoleColor.Cyan;
				c.WriteLine(fileInfo.FullName);
				c.ForegroundColor = ConsoleColor.White;
			}
			else if (!fileInfo.IsBinaryFileExt && !fileInfo.IsBinaryFile())
			{
				files.Add(fileInfo.FullName);
				c.ForegroundColor = ConsoleColor.Cyan;
				c.WriteLine(fileInfo.FullName);
				c.ForegroundColor = ConsoleColor.White;
			}
		}
		else if (Directory.Exists(fileInfo.FullName))
		{
			directories.Add(fileInfo.FullName);
			c.ForegroundColor = ConsoleColor.Cyan;
			c.WriteLine(fileInfo.FullName);
			c.ForegroundColor = ConsoleColor.White;
		}
		else
		{
			// excluded
			c.ForegroundColor = ConsoleColor.Red;
			c.WriteLine(fileInfo.FullName);
			c.ForegroundColor = ConsoleColor.White;
		}
	}
	c.WriteLine($"ℹ first pass added {directories.Count} directories");
	c.WriteLine($"ℹ first pass added {files.Count} files");

	// 2nd pass: fix all included (non-binary) files (remove UTF-8 BOM, remove \r)
	foreach (var file in files)
	{
		Span<byte> bytes = File.ReadAllBytes(file);
		// Remove UTF-8 BOM
		if (bytes is [0xEF, 0xBB, 0xBF, ..])
		{
			bytes = bytes[3..];
		}
		// Remove all \r (carriage return)
		bytes = bytes.IndexOf((byte)'\r') >= 0
			? bytes.ToArray().Where(static b => b != '\r').ToArray()
			: bytes;
		File.WriteAllBytes(file, bytes);
	}

	//var packageRoots = FindPackageRoots().ToArray(); // smart auto-find from current directory
	var packageRoots = GetPackageRoots(gitRoot).ToArray(); // explicitly get package roots (requires packages.json)

	foreach (var (packageRoot, packageName, tomlTable) in packageRoots)
	{
		if (!tomlTable.TryGetValue("meta", out var meta) ||
			meta is not TomlTable metaTable ||
			!metaTable.TryGetValue("version", out var metaVersion) ||
			metaVersion is not string packageVersion ||
			!metaTable.TryGetValue("title", out var metaTitle) ||
			metaTitle is not string packageTitle ||
			!metaTable.TryGetValue("author", out var metaAuthor) ||
			metaAuthor is not string packageAuthor)
		{
			continue;
		}
		c.WriteLine($"ℹ package root: {packageRoot}");
		c.WriteLine($"ℹ package name: {packageName}");
		c.WriteLine($"ℹ package title: {packageTitle}");
		c.WriteLine($"ℹ package author: {packageAuthor}");
		Directory.CreateDirectory(Path.Combine(packageRoot, "Shared"));
		var packageFiles = Directory.GetFiles(packageRoot, "*", SearchOption.AllDirectories);
		c.WriteLine($"ℹ found {packageFiles.Length} files in {packageRoot}");
		var filesList = new List<string>(packageFiles.Length);
		{
			foreach (var file in packageFiles)
			{
				var entryName = Path.GetRelativePath(packageRoot, file).Replace('\\', '/');
				if (!ZipFilterRegexes.Any(r => r.IsMatch('/' + entryName)))
					continue;
				try
				{
					filesList.Add(file);
					c.WriteLine($"ℹ added to filelist: {entryName}");
				}
				catch
				{
					// ignored
				}
			}
		}
		c.WriteLine($"ℹ files after filtering: {filesList.Count}");
		{
			// Find current git tag (if any) matching "v*" and get previous commit hash
			var currentTag = $"v{packageVersion}";
			var numericVersion = 0; // will be set to (amount of "v*" tags) + 1
			var previousCommitHash = "";
			var repoOwner = "";
			var repoName = "";
			using (var repo = new Repository(gitRoot))
			{
				// Extract owner and repo name from remote 'origin'
				var originRemote = repo.Network.Remotes["origin"] ?? repo.Network.Remotes.FirstOrDefault();
				if (originRemote != null)
				{
					var url = originRemote.Url;
					// Parse both HTTPS (https://host/owner/repo.git) and SSH (git@host:owner/repo.git) formats
					if (!string.IsNullOrEmpty(url))
					{
						// Remove .git suffix if present
						if (url.EndsWith(".git"))
							url = url[..^4];
						// Handle SSH format: git@github.com:owner/repo
						if (url.Contains('@'))
						{
							// TODO
						}
						// Handle HTTPS format: https://github.com/owner/repo
						else if (url.Contains('/'))
						{
							//var segments = url.Split('/', 3, StringSplitOptions.RemoveEmptyEntries);
							//if (segments.Length >= 2)
							//{
							//	repoOwner = segments[^2];
							//	repoName = segments[^1];
							//}
							var uri = new Uri(url, UriKind.Absolute);
							var path = uri.AbsolutePath.TrimStart('/');
							var split = path.Split('/', 3, StringSplitOptions.RemoveEmptyEntries);
							if (split.Length >= 2)
							{
								repoOwner = split[0];
								repoName = split[1];
							}
						}
					}
				}
				// Fallback to known values if parsing failed
				if (string.IsNullOrEmpty(repoOwner))
					repoOwner = "Cheatoid";
				if (string.IsNullOrEmpty(repoName))
					repoName = "nanos-world-vault";
				var headCommit = repo.Head.Tip;
				if (headCommit != null)
				{
					// Find the latest tag in the repository matching "v*" (by commit date, not just on HEAD)
					var allVersionTags = repo.Tags
						.Where(static t => t.FriendlyName.StartsWith('v'))
						.Select(static t => new { Tag = t, Commit = t.Target as Commit })
						.Where(static t => t.Commit != null)
						.OrderByDescending(static t => t.Commit!.Committer.When)
						.ToArray();
					// Get the latest tag (most recent commit date)
					var latestTag = allVersionTags.FirstOrDefault();
					currentTag = latestTag?.Tag.FriendlyName ?? $"v{packageVersion}";
					c.WriteLine($"ℹ latest git tag: {currentTag} ({allVersionTags.Length} v* tags found)");
					numericVersion = allVersionTags.Length + 1;
					c.WriteLine($"ℹ numeric version: {numericVersion}");
					// Get the current HEAD commit hash (pre-commit runs before commit, so HEAD is the previous state)
					previousCommitHash = headCommit.Sha;
					c.WriteLine($"ℹ current commit hash: {previousCommitHash}");
				}
			}
			// TODO: Build dependency graph, generate require(), and inject dependencies (OOP framework)
			// Create metadata/version file (metadata_gen.lua under <package root>/Shared folder)
			File.WriteAllText(Path.Combine(packageRoot, "Shared", "metadata_gen.lua"),
				$$"""
				-- <auto-generated> This file has been auto generated. </auto-generated>

				---@class metadata_gen
				---@field timestamp string
				---@field num_version integer
				---@field prev_hash string
				---@field tag string
				---@field owner string
				---@field repo string
				---@field path string
				---@field files string[]

				---@type metadata_gen
				return {
					timestamp = "{{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}}",
					num_version = {{numericVersion}},
					prev_hash = "{{previousCommitHash}}",
					tag = "{{currentTag}}",
					owner = "{{repoOwner}}",
					repo = "{{repoName}}",
					path = "{{Path.GetRelativePath(gitRoot, packageRoot)}}",
					files = {
						{{string.Join("\n\t\t", filesList
							.Select(static f => (path: f, dir: Path.GetDirectoryName(f) ?? ""))
							.OrderBy(static t => t.dir, StringComparer.Ordinal)
							.ThenBy(static t => t.path, StringComparer.Ordinal)
							.Select(t => $"\"{t.path[(packageRoot.Length + 1)..].Replace('\\', '/')}\","))}}
					},
				}
				""".ReplaceLineEndings("\n").Trim() + "\n"
			);
		}
		var zipBytes = CreateZipFromFilesNoFilter(filesList.ToArray(), packageRoot);
		var zipFileSize = zipBytes.Length;
		if (zipFileSize > 0)
		{
			var zipFileName = $"{Path.GetFileName(packageName)}.zip";
			var zipFullPath = Path.Combine(publishFolder, zipFileName);
			File.WriteAllBytes(zipFullPath, zipBytes); // replace existing file
			c.WriteLine(
				$"ℹ created zip: {zipFileSize} bytes -> {Path.Combine(Path.GetFileName(publishFolder), zipFileName)}");
			var zipMd5 = ComputeMD5(zipBytes);
			c.WriteLine($"ℹ zip MD5 hash: {zipMd5}");
			var zipSha1 = ComputeSHA1(zipBytes);
			c.WriteLine($"ℹ zip SHA1 hash: {zipSha1}");
			var zipSha256 = ComputeSHA256(zipBytes);
			c.WriteLine($"ℹ zip SHA256 hash: {zipSha256}");
			if (isReleaseMode)
			{
				File.SetCreationTimeUtc(zipFullPath, DateTime.UnixEpoch);
				File.SetLastWriteTimeUtc(zipFullPath, DateTime.UnixEpoch);
				File.SetLastAccessTimeUtc(zipFullPath, DateTime.UnixEpoch);
				var timeNow = DateTimeOffset.UtcNow.ToUnixTimeSeconds(); // Unix timestamp (force no-cache)
				// Get existing package version (if published)
				var currentPackageVersion = Version.Parse(packageVersion);
				bool shouldUpload;
				var package = await HttpGetJson<Package>($"store/packages/{packageName}?{timeNow}");
				if (package is { success: true, error: null })
				{
					var result = package.result;
					if (result?.Message.ToLowerInvariant() is "package retrieved successfully" &&
						result.payload is { Version.VersionString: not null })
					{
						var publishedPackageVersion = Version.Parse(result.payload.Version.VersionString);
						c.WriteLine($"ℹ current version: {currentPackageVersion}");
						c.WriteLine($"ℹ published version: {publishedPackageVersion}");
						shouldUpload = currentPackageVersion > publishedPackageVersion;
					}
					else
					{
						// Assume package does not exist, first-time upload
						shouldUpload = true;
					}
				}
				else
				{
					// Assume package does not exist, first-time upload
					shouldUpload = true;
				}
#if DEBUG
				//shouldUpload = true; // TODO/REMOVEME
#endif
				if (shouldUpload)
				{
					if (!string.IsNullOrEmpty(cliMode))
					{
						if (!Directory.Exists(cliMode) || !File.Exists(Path.Combine(cliMode, serverFileName)))
						{
							c.Error.WriteLine($"❗ server executable not found: {Path.Combine(cliMode, serverFileName)}");
							return 3;
						}
						isUploadPackagesMode = true;
					}
					else
					{
						// Request presigned URL
						var presign = await HttpGet<PresignResponse>(
							$"store/packages/presign/{packageName}?filename={zipFileName}&size={zipFileSize}",
							apiKey: token
						);
						if (presign is { success: true, content.payload: not null, error: null } &&
						    presign.content.Message.ToLowerInvariant() is "presigned url generated successfully")
						{
							var presignPayload = presign.content.payload;
							var presignedUrl = presignPayload.PresignedUrl;
							var cdnUrl = presignPayload.Url;
							c.WriteLine($"ℹ obtained presigned URL: {presignedUrl}");
							c.WriteLine($"ℹ obtained CDN URL: {cdnUrl}");
							/*
							curl -s -w "\n%{http_code}" \
								-X PUT \
								"$presigned_url" \
								-H "Content-Type: application/zip" \
								--data-binary "@${zip_path}"
							*/
							// Upload zip to presigned URL (Cloudflare R2)
							// TODO/FIXME: I keep getting 404 (not found)...
							var uploadResponse = await HttpSend<byte[], string>(
								url: presignedUrl!.ToString(),
								body: zipBytes,
								httpMethod: HttpMethod.Put,
								//apiKey: token,
								contentType: MediaTypeNames.Application.Zip
							);
							c.WriteLine($"ℹ success: {uploadResponse.success}");
							c.WriteLine($"ℹ upload response: {uploadResponse}");
							if (uploadResponse.success)
							{
								/*
								curl -s -w "\n%{http_code}" \
									-X POST \
									"${api_url}/store/packages/upload/finish" \
									-H "Content-Type: application/json" \
									-H "Authorization: Token ${token}" \
									--data-raw "{\"name\":\"${package_name}\",\"url\":\"${cdn_url}\"}"
								*/
								// Finalize upload...
								var finishResponse = await HttpSend<Dictionary<string, string>, string>(
									url: $"store/packages/upload/finish",
									//body: (name: packageName, url: cdnUrl!.ToString()),
									body: new()
									{
										{ "name", packageName },
										{ "url", cdnUrl!.ToString() }
									},
									httpMethod: HttpMethod.Post,
									apiKey: token,
									contentType: MediaTypeNames.Application.Json
								);
								c.WriteLine($"ℹ success: {finishResponse.success}");
								c.WriteLine($"ℹ finish response: {finishResponse.result}");
								if (finishResponse.success)
								{
									c.WriteLine("🚀 uploaded to nanos world store");
								}
								else
								{
									c.Error.WriteLine("❗ error: something went wrong during finish");
									c.Error.WriteLine(finishResponse.error ?? "unknown error");
									//return 5;
								}
							}
							else
							{
								c.Error.WriteLine("❗ error: something went wrong during upload");
								c.Error.WriteLine(uploadResponse.error ?? "unknown error");
								//return 4;
							}
						}
						else
						{
							c.Error.WriteLine("❗ error: something went wrong during presign request");
							c.Error.WriteLine(presign.error?.Message ?? "unknown error");
							//return 3;
						}
					}
				}
			}
		}
		else
		{
			c.Error.WriteLine("❗ error: no files to zip");
			//return 2;
		}
		c.WriteLine();
	}

	// Handle --upload-packages and --release
	if (isUploadPackagesMode)
	{
		// Setup paths (mirroring PowerShell script)
		var vaultRoot = gitRoot; // The vault root is the git root
		var serverRoot = string.IsNullOrEmpty(cliMode)
			? (Path.GetDirectoryName(vaultRoot) ?? vaultRoot) // assume it is in the upper directory
			: cliMode;
		var packagesDir = Path.Combine(serverRoot, "Packages");
		var publishDir = Path.Combine(vaultRoot, "publish");
		var packagesJsonPath = Path.Combine(vaultRoot, "packages.json");

		if (!File.Exists(packagesJsonPath))
		{
			c.Error.WriteLine($"❗ error: packages.json not found at: {packagesJsonPath}");
			continue;
		}

		// Read packages.json
		var packagesMap = JsonSerializer.Deserialize<Dictionary<string, string>>(
			File.ReadAllText(packagesJsonPath), JsonOptions.Instance)!;

		// Filter to single package if specified
		var packagesToProcess = singlePackage is not null
			? packagesMap.Where(kvp => kvp.Key == singlePackage || kvp.Value == singlePackage)
				.ToDictionary(static kvp => kvp.Key, kvp => kvp.Value)
			: packagesMap;

		if (packagesToProcess.Count == 0)
		{
			c.Error.WriteLine("❗ error: no packages to process");
			continue;
		}

		Directory.CreateDirectory(publishDir);
		foreach (var (folderName, packageName) in packagesToProcess)
		{
			c.WriteLine($"ℹ processing package: {packageName}");

			// Build the package (reuse existing logic)
			var packageRoot = Path.Combine(vaultRoot, folderName);
			if (!Directory.Exists(packageRoot))
			{
				c.Error.WriteLine($"❗ error: package folder not found: {packageRoot}");
				continue;
			}

			// Create zip using existing logic
			var packageTomlPath = Path.Combine(packageRoot, PackageToml);
			if (!File.Exists(packageTomlPath))
			{
				c.Error.WriteLine($"❗ error: {PackageToml} not found in {packageRoot}");
				continue;
			}

			var toml = File.ReadAllText(packageTomlPath);
			var tomlTable = TomlSerializer.Deserialize<TomlTable>(toml);
			if (tomlTable is null)
			{
				c.Error.WriteLine($"❗ error: failed to parse {PackageToml}");
				continue;
			}

			var packageFiles = Directory.EnumerateFiles(packageRoot, "*", SearchOption.AllDirectories);
			var zipBytes = CreateZipFromFiles(packageFiles.ToArray(), packageRoot, ZipFilterRegexes);
			var zipFileSize = zipBytes.Length;
			if (zipFileSize <= 0)
			{
				c.Error.WriteLine($"❗ error: no files to zip for package {packageName}");
				continue;
			}

			var zipFileName = $"{packageName}.zip";
			var zipFullPath = Path.Combine(publishDir, zipFileName);
			await File.WriteAllBytesAsync(zipFullPath, zipBytes);
			c.WriteLine($"ℹ created zip: {zipFileSize} bytes -> {Path.Combine("publish", zipFileName)}");

			// Verify the zip file is valid before extraction
			try
			{
				await using var verifyStream = File.OpenRead(zipFullPath);
				await using var verifyZip = new ZipArchive(verifyStream, ZipArchiveMode.Read);
				if (verifyZip.Entries.Count == 0)
				{
					c.Error.WriteLine("❗ error: zip file has no entries");
					continue;
				}
			}
			catch (Exception ex)
			{
				c.Error.WriteLine($"❗ error: zip file is corrupted: {ex.Message}");
				continue;
			}

			var packagePath = Path.Combine(packagesDir, packageName);

			// Handle --release switch
			if (isReleaseMode)
			{
				c.WriteLine($"ℹ removing extracted {packageName} folder");
				if (Directory.Exists(packagePath))
				{
					try
					{
						Directory.Delete(packagePath, recursive: true);
					}
					catch
					{
						// ignored
					}
				}
				c.WriteLine("ℹ extracting zipped package");
				var extractionSuccess = false;
				Exception? lastExtractionError = null;
				for (var retry = 0; retry <= 3; retry++)
				{
					if (retry > 0)
					{
						c.WriteLine($"ℹ retry attempt {retry}/3 after 500ms delay...");
						await Task.Delay(500);
					}
					try
					{
						if (Directory.Exists(packagePath))
						{
							try
							{
								Directory.Delete(packagePath, recursive: true);
							}
							catch
							{
								// ignored
							}
						}
						Directory.CreateDirectory(packagePath);
						ZipFile.ExtractToDirectory(zipFullPath, packagePath, overwriteFiles: true);
						extractionSuccess = true;
						break;
					}
					catch (Exception ex)
					{
						lastExtractionError = ex;
						c.WriteLine($"⚠ extraction attempt {retry + 1} failed: {ex.Message}");
					}
				}
				if (!extractionSuccess)
				{
					c.Error.WriteLine(
						$"❗ error: failed to extract zip after 3 attempts: {lastExtractionError?.Message}");
					continue;
				}
				// Upload using NanosWorldServer
				c.WriteLine("ℹ uploading package");
				var serverExePath = Path.Combine(serverRoot, serverFileName);
				if (!File.Exists(serverExePath))
				{
					c.Error.WriteLine($"❗ server executable not found: {serverExePath}");
					continue;
				}
				var serverConfig = Path.Combine(serverRoot, "Config.toml");
				if (!File.Exists(serverConfig))
				{
					c.WriteLine("ℹ Config.toml not found, generating by running server briefly...");
					try
					{
						var psiConfig = new ProcessStartInfo
						{
							FileName = serverExePath,
							RedirectStandardOutput = true,
							RedirectStandardError = true,
							UseShellExecute = false,
							CreateNoWindow = true,
							WorkingDirectory = Path.GetDirectoryName(serverExePath)
						};
						psiConfig.ArgumentList.Add("--token");
						psiConfig.ArgumentList.Add(token!);
						psiConfig.ArgumentList.Add("--save");
						using var configProcess = Process.Start(psiConfig);
						if (configProcess is null)
						{
							c.Error.WriteLine($"❗ error: failed to start {serverFileName} to generate Config.toml");
							continue;
						}
						await Task.Delay(TimeSpan.FromSeconds(5));
						try
						{
							configProcess.Kill(true);
						}
						catch
						{
							// Process may have already exited
						}
						await configProcess.WaitForExitAsync();
						c.WriteLine("ℹ Config.toml generated successfully");
					}
					catch (Exception ex)
					{
						c.Error.WriteLine($"❗ error: failed to generate Config.toml: {ex.Message}");
						continue;
					}
				}

				try
				{
					var psi = new ProcessStartInfo
					{
						FileName = serverExePath,
						RedirectStandardOutput = true,
						RedirectStandardError = true,
						UseShellExecute = false,
						CreateNoWindow = true,
						WorkingDirectory = Path.GetDirectoryName(serverExePath)
					};
					// Use ArgumentList instead of Arguments for proper escaping
					//psi.ArgumentList.Add("--token"); // Token saved in Config.toml
					//psi.ArgumentList.Add(token);
					psi.ArgumentList.Add("--cli");
					psi.ArgumentList.Add("upload");
					psi.ArgumentList.Add("package");
					psi.ArgumentList.Add(packageName);
					using var process = Process.Start(psi);
					if (process is null)
					{
						c.Error.WriteLine($"❗ error: failed to start {serverFileName}");
						continue;
					}
					await process.WaitForExitAsync();
					if (process.ExitCode != 0)
					{
						var stderr = await process.StandardError.ReadToEndAsync();
						c.Error.WriteLine($"❗ error: upload failed (exit code: {process.ExitCode}): {stderr}");
						continue;
					}
					c.WriteLine("ℹ upload successful");
				}
				catch (Exception ex)
				{
					c.Error.WriteLine($"❗ error: upload command failed: {ex.Message}");
					continue;
				}
			}

			// Remove extracted folder and create symbolic link
			c.WriteLine($"ℹ removing extracted {packageName} folder");
			try
			{
				Directory.Delete(packagePath, recursive: true);
			}
			catch
			{
				// ignored
			}

			c.WriteLine($"ℹ creating symbolic-link {packageName} folder");
			try
			{
				// Use Junction for directories (works without admin on Windows)
				var junction = new JunctionPoint(packagePath, packageRoot);
				junction.Create();
				c.WriteLine($"ℹ created symbolic-link: {packagePath} -> {packageRoot}");
			}
			catch (Exception ex)
			{
				c.WriteLine(
					$"⚠ warning: failed to create symbolic-link (run as admin for symlink support): {ex.Message}");
				// Fallback: just copy the files or leave as extracted
			}
		}
	}

	break;
}

// Fetch all packages in nanos world store:
//var packages = await HttpGetJson<Packages>("store/packages");
//if (packages is { success: true, result: not null })
//{
//	var result = packages.result;
//	if (result is { payload.Packages.Length: > 0 })
//	{
//		foreach (var package in result.payload.Packages)
//		{
//			c.WriteLine($"{package.Name} : v{package.Version!.VersionString}");
//		}
//	}
//}

// Convert package JSON string to C# typed model:
//var typedPackage = Package.FromJson(
//	"""
//	{
//	  "message": "Package retrieved successfully",
//	  "request_id": "0000000000000000-XXX",
//	  "payload": {
//	    "id": "6604e8fb-cb9b-4350-a342-e7fb0498b8dd",
//	    "user_id": "2a94d978-44f6-43e4-96a0-b0fba2b4a91f",
//	    "name": "discord",
//	    "description": "Add the following keys in Packages/.data/discord.toml\n\ndiscord_webhook_id = \"\"\ndiscord_webhook_token = \"\"\n\nOr start the server with the command-line: --custom_settings \"discord_webhook_id='X', discord_webhook_token='Y'\"\n\nTo get them, first create an webhook (https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks) and copy the Webhook URL.\n\nThen you can extract the discord_webhook_id and discord_webhook_token from the Webhook URL:\n\nhttps://discord.com/api/webhooks/\u003Cdiscord_webhook_id\u003E/\u003Cdiscord_webhook_token\u003E",
//	    "short_description": "Discord Webhook Integration",
//	    "title": "Discord",
//	    "type": "script",
//	    "icon_url": null,
//	    "cover_url": "https://cdn.nanos-world.com/images/discord/1766087170_5541dcbd-8ead-4c2e-a6a1-860f7d169c92.jpg",
//	    "images": [],
//	    "github_url": "",
//	    "download_count": 76,
//	    "view_count": 55,
//	    "download_url": "https://api.nanos-world.com/store/packages/discord/download",
//	    "published": true,
//	    "ratings": {
//	      "total": 0,
//	      "average": 0,
//	      "one_star": 0,
//	      "two_star": 0,
//	      "three_star": 0,
//	      "four_star": 0,
//	      "five_star": 0
//	    },
//	    "links": null,
//	    "tags": [
//	      {
//	        "id": "7233b32c-661e-4d54-9133-9ab3a8d67819",
//	        "created_at": "2025-10-21T10:06:42.335659Z",
//	        "updated_at": "2025-10-21T10:06:47.639787Z",
//	        "deleted_at": null,
//	        "name": "integration",
//	        "slug": "integration",
//	        "description": "Integration",
//	        "color": "#6B7280",
//	        "icon": "",
//	        "usage_count": 1
//	      }
//	    ],
//	    "team_id": "c26ee637-8eef-485f-a7a4-3f40a8b3386d",
//	    "team": {
//	      "id": "c26ee637-8eef-485f-a7a4-3f40a8b3386d",
//	      "name": "SyedMuhammad Team",
//	      "description": "Personal team for SyedMuhammad",
//	      "icon_url": "https://cdn.nanos-world.com/icons/1769780151_2d21d65b-4d50-493c-92f1-877c2ac72f7d.jpeg"
//	    },
//	    "version": {
//	      "id": "984c51cd-81c1-48d7-a990-84c2990eef86",
//	      "package_id": "6604e8fb-cb9b-4350-a342-e7fb0498b8dd",
//	      "version": "0.3.0",
//	      "status": "released",
//	      "changelog": "",
//	      "validated_at": "2025-10-16T16:29:36.196545Z",
//	      "upload_date": "2025-10-16T16:29:28.341348Z",
//	      "download_url": "https://api.nanos-world.com/store/packages/discord/versions/0.3.0/download",
//	      "zip_size_bytes": 2107,
//	      "extracted_size_bytes": 5230,
//	      "parsed_author": "SyedMuhammad",
//	      "created_at": "2025-10-16T16:29:28.327647Z",
//	      "updated_at": "2025-10-16T16:30:14.164916Z",
//	      "toml_url": "https://cdn.nanos-world.com/984c51cd-81c1-48d7-a990-84c2990eef86.toml",
//	      "script": {
//	        "force_no_map_package": false,
//	        "auto_cleanup": true,
//	        "load_level_entities": false,
//	        "compatibility_version": "1.92",
//	        "package_requirements": [],
//	        "assets_requirements": [],
//	        "compatible_maps": []
//	      }
//	    },
//	    "package_versions": [
//	      {
//	        "id": "984c51cd-81c1-48d7-a990-84c2990eef86",
//	        "package_id": "6604e8fb-cb9b-4350-a342-e7fb0498b8dd",
//	        "version": "0.3.0",
//	        "status": "released",
//	        "changelog": "",
//	        "validated_at": "2025-10-16T16:29:36.196545Z",
//	        "upload_date": "2025-10-16T16:29:28.341348Z",
//	        "download_url": "https://api.nanos-world.com/store/packages/discord/versions/0.3.0/download",
//	        "zip_size_bytes": 2107,
//	        "extracted_size_bytes": 5230,
//	        "parsed_author": "SyedMuhammad",
//	        "created_at": "2025-10-16T16:29:28.327647Z",
//	        "updated_at": "2025-10-16T16:30:14.164916Z",
//	        "toml_url": "https://cdn.nanos-world.com/984c51cd-81c1-48d7-a990-84c2990eef86.toml",
//	        "script": {
//	          "force_no_map_package": false,
//	          "auto_cleanup": true,
//	          "load_level_entities": false,
//	          "compatibility_version": "1.92",
//	          "package_requirements": [],
//	          "assets_requirements": [],
//	          "compatible_maps": []
//	        }
//	      }
//	    ],
//	    "created_at": "2025-10-16T16:28:22.466502Z",
//	    "updated_at": "2026-04-04T18:53:46.72432Z",
//	    "price_in_cents": 0
//	  }
//	}
//	"""
//);

return 0;

static string ComputeMD5(byte[] data)
{
	var hash = MD5.HashData(data);
	return Convert.ToHexString(hash).ToLowerInvariant();
}

static string ComputeSHA1(byte[] data)
{
	var hash = SHA1.HashData(data);
	return Convert.ToHexString(hash).ToLowerInvariant();
}

static string ComputeSHA256(byte[] data)
{
	var hash = SHA256.HashData(data);
	return Convert.ToHexString(hash).ToLowerInvariant();
}

static bool IsValueTupleType(Type type)
{
	if (!type.IsGenericType)
		return false;
	var genericType = type.GetGenericTypeDefinition();
	return genericType == typeof(ValueTuple<>)
	       || genericType == typeof(ValueTuple<,>)
	       || genericType == typeof(ValueTuple<,,>)
	       || genericType == typeof(ValueTuple<,,,>)
	       || genericType == typeof(ValueTuple<,,,,>)
	       || genericType == typeof(ValueTuple<,,,,,>)
	       || genericType == typeof(ValueTuple<,,,,,,>)
	       || genericType == typeof(ValueTuple<,,,,,,,>);
}

static Dictionary<string, object?> ConvertValueTupleToDictionary<T>(T tuple)
{
	var type = typeof(T);
	var fields = type.GetFields();
	var dict = new Dictionary<string, object?>();

	// Get TupleElementNames from the calling method's generic type argument
	// The attribute is stored on the method signature, not the runtime type
	string?[]? tupleNames = null;
	try
	{
		var stackTrace = new StackTrace(1, false); // Skip this frame
		for (var i = 0; i < stackTrace.FrameCount; ++i)
		{
			var frame = stackTrace.GetFrame(i);
			if (frame == null) continue;
			var method = frame.GetMethod();
			if (method == null) continue;

			// Check if this method has a generic return type that matches our tuple type
			if (method is MethodInfo { IsGenericMethod: true } methodInfo)
			{
				// Get the generic method definition (has the original type parameters with attributes)
				var methodDef = methodInfo.GetGenericMethodDefinition();
				var genericArgs = methodDef.GetGenericArguments();
				foreach (var t in genericArgs)
				{
					// Use GetCustomAttributesData to read raw metadata
					var attrData = t.GetCustomAttributesData()
						.FirstOrDefault(a =>
							a.AttributeType.FullName == "System.Runtime.CompilerServices.TupleElementNamesAttribute");
					if (attrData != null && attrData.ConstructorArguments.Count > 0)
					{
						var namesArg = attrData.ConstructorArguments[0];
						if (namesArg.Value is IList<CustomAttributeTypedArgument> namesList &&
						    namesList.Count == fields.Length)
						{
							tupleNames = namesList.Select(n => n.Value as string).ToArray();
							break;
						}
					}
				}
				if (tupleNames != null) break;
			}
		}
	}
	catch
	{
		// Ignore stack trace errors, fall back to ItemN names
	}

	for (var i = 0; i < fields.Length; ++i)
	{
		var field = fields[i];
		// Use the actual name from TupleElementNames if available, otherwise use ItemN
		var key = tupleNames != null && i < tupleNames.Length && tupleNames[i] != null
			? tupleNames[i]!
			: field.Name;
		dict[key] = field.GetValue(tuple);
	}

	return dict;
}

string? FindGitRoot(string startPath)
{
	// Find the root of the git repository (from nested path)
	var dir = new DirectoryInfo(startPath);
	while (dir != null)
	{
		if (Directory.Exists(Path.Combine(dir.FullName, ".git")))
			return dir.FullName;
		dir = dir.Parent;
	}
	return null;
}

HashSet<string> GetPathsNotIgnored(string repoPath)
{
	using var repo = new Repository(repoPath);
	var files = new HashSet<string>();
	var rootDir = repo.Info.WorkingDirectory;
	if (rootDir is null)
		return files;
	// Build a dictionary of submodule repos for ignore handling
	var submoduleRepos = new Dictionary<string, Repository>(StringComparer.OrdinalIgnoreCase);
	foreach (var submodule in repo.Submodules)
	{
		var submodulePath = Path.Combine(rootDir, submodule.Path);
		if (Repository.IsValid(submodulePath))
		{
			var submoduleRepo = new Repository(submodulePath);
			submoduleRepos[submodule.Path.TrimEnd('/') + '/'] = submoduleRepo;
		}
	}
	try
	{
		foreach (var file in Directory.EnumerateFiles(rootDir, "*", SearchOption.AllDirectories))
		{
			var relativePath = Path.GetRelativePath(rootDir, file).Replace('\\', '/');
			// Check if this file is inside a submodule
			var submoduleEntry = submoduleRepos
				.FirstOrDefault(s => relativePath.StartsWith(s.Key, StringComparison.OrdinalIgnoreCase));
			if (submoduleEntry.Value is not null)
			{
				// Get the path relative to the submodule root
				var submoduleRelativePath = relativePath[submoduleEntry.Key.Length..];
				// Check against submodule's gitignore
				if (submoduleEntry.Value.Ignore.IsPathIgnored(submoduleRelativePath))
					continue;
				files.Add(relativePath);
				continue;
			}
			// Check against main repo's gitignore
			if (repo.Ignore.IsPathIgnored(relativePath))
				continue;
			files.Add(relativePath);
		}
	}
	finally
	{
		// Dispose all submodule repos
		foreach (var (_, subRepo) in submoduleRepos)
			subRepo.Dispose();
	}
	return files;
}

IEnumerable<(string PackageRoot, string PackageName, TomlTable TomlTable)>
	GetPackageRoots(string packagesJsonDir)
{
	var packagesMap = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(
		Path.Combine(packagesJsonDir, "packages.json")), JsonOptions.Instance)!;
	foreach (var (folderName, packageName) in packagesMap)
	{
		var packageToml = File.ReadAllText(Path.GetFullPath(Path.Combine(
			packagesJsonDir, folderName, PackageToml)));
		yield return (folderName, packageName, TomlSerializer.Deserialize<TomlTable>(packageToml)!);
	}
}

IEnumerable<(string PackageRoot, TomlTable TomlTable)>
	FindPackageRoots(string? startPath = null)
{
	startPath ??= Directory.GetCurrentDirectory();
	foreach (var file in Directory.EnumerateFiles(startPath, PackageToml, SearchOption.AllDirectories))
	{
		// Parse and validate TOML using pooled buffers
		using var fs = new FileStream(file,
			FileMode.Open, FileAccess.Read, FileShare.Read, 8192, FileOptions.SequentialScan);
		var length = (int)fs.Length;
		if (length == 0) continue;

		byte[]? rented = null;
		string? toml;
		try
		{
			rented = ArrayPool<byte>.Shared.Rent(length);
			fs.ReadExactly(rented, 0, length);
			toml = Encoding.UTF8.GetString(rented.AsSpan(0, length));
		}
		finally
		{
			if (rented != null)
				ArrayPool<byte>.Shared.Return(rented);
		}

		var model = TomlSerializer.Deserialize<TomlTable>(toml);
		if (model is null)
			continue;

		yield return (Path.GetDirectoryName(file)!, model);
	}
}

void CreateZipFromRepo(
	string repoPath,
	string sourceFolder,
	string zipPath,
	string[]? fileExtensions = null
)
{
	var allFiles = GetPathsNotIgnored(repoPath);
	// Convert sourceFolder to a path relative to repo root
	var relativeSource = Path.GetRelativePath(repoPath, sourceFolder).Replace('\\', '/');
	var sourcePrefix = relativeSource.EndsWith('/') ? relativeSource : relativeSource + '/';
	var files = allFiles.Where(f => f.StartsWith(sourcePrefix) || f == relativeSource).ToHashSet();
	if (fileExtensions?.Length > 0)
	{
		var extSet = fileExtensions
			.Select(static e => e.StartsWith('.') ? e.ToLowerInvariant() : '.' + e.ToLowerInvariant())
			.ToHashSet();
		files = files.Where(f => extSet.Contains(Path.GetExtension(f).ToLowerInvariant())).ToHashSet();
	}
	try
	{
		File.Delete(zipPath);
	}
	catch
	{
		// ignored
	}
	using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);
	foreach (var file in files)
	{
		var fullPath = Path.Combine(repoPath, file);
		if (File.Exists(fullPath))
		{
			var entryName = file[sourcePrefix.Length..];
			zip.CreateEntryFromFile(fullPath, entryName, CompressionLevel.SmallestSize);
		}
	}
	c.WriteLine($"Created zip at '{zipPath}' with {files.Count} files");
}

byte[] CreateZipInMemory(HashSet<string> filePaths, string? basePath = null)
{
	using var ms = new MemoryStream();
	// Use leaveOpen: true so disposing zip doesn't close the stream
	using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
	{
		foreach (var file in filePaths)
		{
			//if (!File.Exists(file))
			//	continue;
			var entryName = basePath != null && file.StartsWith(basePath)
				? file[basePath.Length..].TrimStart('/', '\\')
				: Path.GetFileName(file);
			try
			{
				zip.CreateEntryFromFile(file, entryName, CompressionLevel.SmallestSize);
			}
			catch
			{
				// ignored
			}
		}
	} // zip disposed here - writes central directory to stream
	return ms.ToArray();
}

static byte[] CreateZipFromFiles(
	string[] files,
	string basePath,
	Regex[] includeEntryNameRegexes
)
{
	using var ms = new MemoryStream();
	// Use leaveOpen: true so disposing zip doesn't close the stream
	using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
	{
		foreach (var file in files)
		{
			var entryName = Path.GetRelativePath(basePath, file).Replace('\\', '/');
			if (!includeEntryNameRegexes.Any(r => r.IsMatch('/' + entryName)))
				continue;
			try
			{
				c.WriteLine($"ℹ adding file to zip: {entryName}");
				zip.CreateEntryFromFile(file, entryName, CompressionLevel.SmallestSize);
			}
			catch
			{
				// ignored
			}
		}
	} // zip disposed here - writes central directory to stream
	return ms.ToArray();
}

static byte[] CreateZipFromFilesNoFilter(
	string[] files,
	string basePath
)
{
	using var ms = new MemoryStream();
	// Use leaveOpen: true so disposing zip doesn't close the stream
	using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
	{
		foreach (var file in files)
		{
			var entryName = Path.GetRelativePath(basePath, file).Replace('\\', '/');
			// Files are already filtered above, no need to filter again
			try
			{
				c.WriteLine($"ℹ adding file to zip: {entryName}");
				zip.CreateEntryFromFile(file, entryName, CompressionLevel.SmallestSize);
			}
			catch
			{
				// ignored
			}
		}
	} // zip disposed here - writes central directory to stream
	return ms.ToArray();
}

void ExtractZip(string zipPath, string extractPath)
{
	Directory.CreateDirectory(extractPath);
	ZipFile.ExtractToDirectory(zipPath, extractPath, overwriteFiles: true);
	c.WriteLine($"Extracted '{zipPath}' to '{extractPath}'");
}

async Task<(bool success, T? content, Exception? error)>
	HttpGet<T>(
		string url,
		string? apiKey = null,
		CancellationToken ct = default
	)
	where T : class
{
	try
	{
		using var request = new HttpRequestMessage(HttpMethod.Get, url);
		//request.Headers.Add("Content-Type", MediaTypeNames.Application.Json);
		if (!string.IsNullOrEmpty(apiKey))
		{
			request.Headers.Add("X-API-Key", apiKey);
			request.Headers.Authorization = new AuthenticationHeaderValue("Token", apiKey);
		}
		using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
		//var response = await http.GetAsync(url, HttpCompletionOption.ResponseContentRead, ct);
		using var responseContent = response.Content;
		if (typeof(T) == typeof(string))
			return (response.IsSuccessStatusCode, (T?)(object?)await responseContent.ReadAsStringAsync(ct), null);
		if (typeof(T) == typeof(byte[]))
			return (response.IsSuccessStatusCode, (T?)(object?)await responseContent.ReadAsByteArrayAsync(ct), null);
		return (response.IsSuccessStatusCode, await responseContent.ReadFromJsonAsync<T>(ct), null);
	}
	catch (Exception ex)
	{
		return (false, null, ex);
	}
}

async Task<(bool success, byte[]? content)>
	HttpGetBytes(
		string url,
		CancellationToken ct = default,
		IProgress<double>? progress = null,
		int chunkSize = 8192
	)
{
	try
	{
		using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
		using var responseContent = response.Content;
		if (!response.IsSuccessStatusCode) // 2xx
			return (false, await responseContent.ReadAsByteArrayAsync(ct));
		var totalBytes = responseContent.Headers.ContentLength ?? -1;
		await using var stream = await responseContent.ReadAsStreamAsync(ct);
		using var ms = new MemoryStream();
		var buffer = ArrayPool<byte>.Shared.Rent(chunkSize);
		try
		{
			var readBytes = 0L;
			int bytesRead;
			while ((bytesRead = await stream.ReadAsync(buffer, ct)) > 0)
			{
				await ms.WriteAsync(buffer.AsMemory(0, bytesRead), ct);
				readBytes += bytesRead;
				if (totalBytes > 0 && progress != null)
					progress.Report((double)readBytes / totalBytes);
			}
		}
		finally
		{
			ArrayPool<byte>.Shared.Return(buffer);
		}
		return (true, ms.ToArray());
	}
	catch (Exception)
	{
		return (false, null);
	}
}

async Task<(bool success, T? result, Exception? error)>
	HttpGetJson<T>(
		string url,
		CancellationToken ct = default
	)
	where T : class
{
	try
	{
		using var request = new HttpRequestMessage(HttpMethod.Get, url);
		//request.Headers.Add("Accept", MediaTypeNames.Application.Json);
		using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
		//response.EnsureSuccessStatusCode();
		using var responseContent = response.Content;
		var content = await responseContent.ReadAsStringAsync(ct);
		if (!response.IsSuccessStatusCode) // 2xx
			return (false, null, new Exception(content));
		var result = JsonSerializer.Deserialize<T>(content, JsonOptions.Instance);
		return (true, result, null);
	}
	catch (Exception ex)
	{
		return (false, null, ex);
	}
}

async Task<(bool success, TResponse? result, string? error)>
	HttpSend<TRequest, TResponse>(
		string url,
		TRequest body,
		HttpMethod? httpMethod = null,
		string? apiKey = null,
		string? contentType = null,
		CancellationToken ct = default
	)
	where TResponse : class
{
	try
	{
		using var request = new HttpRequestMessage(httpMethod ?? HttpMethod.Post, url);
		//request.Headers.Add("Accept", MediaTypeNames.Application.Json);
		if (typeof(TRequest) == typeof(byte[]))
		{
			var input = (byte[]?)(object?)body;
			if (input is not null)
			{
				request.Content = new ByteArrayContent(input);
			}
		}
		else
		{
			string json;
			// Support variadic ValueTuple (convert to dictionary key-value)
			if (IsValueTupleType(typeof(TRequest)))
			{
				var dict = ConvertValueTupleToDictionary(body);
				json = JsonSerializer.Serialize(dict);
			}
			else
			{
				json = JsonSerializer.Serialize(body);
			}
			request.Content = new StringContent(json, Encoding.UTF8, MediaTypeNames.Application.Json);
		}
		if (request.Content is not null)
		{
			request.Content!.Headers.ContentType =
				new MediaTypeHeaderValue(contentType ?? MediaTypeNames.Application.Json);
		}
		try
		{
			if (!string.IsNullOrEmpty(apiKey))
			{
				request.Headers.Add("X-API-Key", apiKey);
				request.Headers.Authorization = new AuthenticationHeaderValue("Token", apiKey);
			}
			using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
			//response.EnsureSuccessStatusCode();
			using var responseContent = response.Content;
			var content = await responseContent.ReadAsStringAsync(ct);
			if (!response.IsSuccessStatusCode) // 2xx
				return (false, null, content);
			var result = JsonSerializer.Deserialize<TResponse>(content, JsonOptions.Instance);
			return (true, result, null);
		}
		finally
		{
			request.Content?.Dispose();
		}
	}
	catch (Exception ex)
	{
		return (false, null, ex.Message);
	}
}

internal static partial class Program
{
	private const RegexOptions RegexFlags =
			RegexOptions.IgnoreCase
			| RegexOptions.Compiled
			| RegexOptions.Singleline
			| RegexOptions.IgnorePatternWhitespace
			| RegexOptions.RightToLeft // for performance
		//| RegexOptions.NonBacktracking
		;

	private static readonly Regex ZipFilesFilterRegex, ZipAdditionalFilesRegex;
	private static readonly Regex[] ZipFilterRegexes;
	private static readonly string ToolVersion;

	static Program()
	{
		ZipFilesFilterRegex = new(@"\.(css|html|js|lua|toml)$", RegexFlags); // TODO/CONS: add .md ?
		ZipAdditionalFilesRegex = new(@"/(LICENSE|README\.md)$", RegexFlags);
		ZipFilterRegexes = [ZipFilesFilterRegex, ZipAdditionalFilesRegex];
		var executingAssembly = Assembly.GetExecutingAssembly();
		ToolVersion =
			executingAssembly.GetCustomAttribute<AssemblyVersionAttribute>()?.Version ??
			executingAssembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ??
			"0.0.0";
	}

	extension(FileInfo fileInfo)
	{
		public bool IsBinaryFileExt => fileInfo.Extension.ToLowerInvariant() is
			".bin" or
			".pdb" or
			".dll" or
			".dat" or
			".exe" or
			".msi" or
			".so" or
			".dylib" or
			".wasm" or
			".jar" or
			//".bat" or
			//".cmd" or
			//".sh" or
			//".ps1" or
			".cache" or
			".com" or
			".msi" or
			".deb" or
			".rpm" or
			".app" or
			".ipa" or
			".apk" or
			".xapk" or
			".msi" or
			".jpg" or
			".jpeg" or
			".png" or
			".gif" or
			".tga" or
			".bmp" or
			".ico" or
			".webp" or
			".tiff" or
			".tif" or
			".raw" or
			".heic" or
			".heif" or
			".psd" or
			".ai" or
			".eps" or
			".svg" or
			".svgz" or
			".mp3" or
			".mp4" or
			".wav" or
			".ogg" or
			".m4a" or
			".opus" or
			".flac" or
			".aac" or
			".wma" or
			".avi" or
			".mov" or
			".mkv" or
			".flv" or
			".webm" or
			".wmv" or
			".ttf" or
			".otf" or
			".woff" or
			".woff2" or
			".eot" or
			".pdf" or
			".doc" or
			".docx" or
			".xls" or
			".xlsx" or
			".ppt" or
			".pptx" or
			".odt" or
			".ods" or
			".odp" or
			".rtf" or
			".msg" or
			".eml" or
			".db" or
			".sqlite" or
			".mdb" or
			".accdb" or
			".fbx" or
			".obj" or
			".gltf" or
			".glb" or
			".blend" or
			".3ds" or
			".dae" or
			".uasset" or
			//".uplugin" or
			//".uproject" or
			".upk" or
			".pak" or
			".unitypackage" or
			".pfx" or
			".p12" or
			".key" or
			".der" or
			".cer" or
			".crt" or
			".pub" or
			".7z" or
			".rar" or
			".zip" or
			".tar" or
			".gz" or
			".bz2" or
			".bzip" or
			".xz" or
			".tgz" or
			".tbz2" or
			".txz" or
			".cab" or
			".lzh" or
			".lha" or
			".arj" or
			".a" or
			".lib" or
			".dem" or
			".vcd" or
			".gma" or
			".mdl" or
			".phy" or
			".vvd" or
			".vtx" or
			".ani" or
			".vtf";

		public byte[] ReadAllBytes()
		{
			using var fileStream = fileInfo.OpenRead();
			var buffer = new byte[fileStream.Length];
			_ = fileStream.Read(buffer, 0, buffer.Length);
			return buffer;
		}

		public byte[] ReadAllBytesMemoryMapped()
		{
			using var fileStream = fileInfo.Open(FileMode.Open, FileAccess.Read, FileShare.Read);
			using var memoryMappedFile = MemoryMappedFile.CreateFromFile(
				fileStream,
				null, // map name (null for non-persisted)
				fileStream.Length,
				MemoryMappedFileAccess.Read,
				HandleInheritability.None,
				false);
			using var accessor = memoryMappedFile.CreateViewAccessor(0, fileStream.Length, MemoryMappedFileAccess.Read);
			var length = (int)fileStream.Length;
			var buffer = new byte[length];
			accessor.ReadArray(0, buffer, 0, length);
			return buffer;
		}

		public void ReadBytesChunked(Func<byte[], int, bool> processChunk, int chunkSize = 8192)
		{
			using var fileStream = fileInfo.OpenRead();
			var chunk = ArrayPool<byte>.Shared.Rent(chunkSize);
			try
			{
				int bytesRead;
				while ((bytesRead = fileStream.Read(chunk, 0, chunkSize)) > 0)
				{
					if (!processChunk(chunk, bytesRead))
						break;
				}
			}
			finally
			{
				ArrayPool<byte>.Shared.Return(chunk);
			}
		}

		public void ReadBytesChunkedMemoryMapped(Func<byte[], int, bool> processChunk, int chunkSize = 8192)
		{
			using var fileStream = fileInfo.Open(FileMode.Open, FileAccess.Read, FileShare.Read);
			using var memoryMappedFile = MemoryMappedFile.CreateFromFile(
				fileStream,
				null, // map name (null for non-persisted)
				fileStream.Length,
				MemoryMappedFileAccess.Read,
				HandleInheritability.None,
				false);
			using var accessor = memoryMappedFile.CreateViewAccessor(0, fileStream.Length, MemoryMappedFileAccess.Read);
			var chunk = ArrayPool<byte>.Shared.Rent(chunkSize);
			try
			{
				var position = 0L;
				var length = fileStream.Length;
				while (position < length)
				{
					var remain = length - position;
					var bytesToRead = chunkSize < remain ? chunkSize : remain;
					var bytesRead = accessor.ReadArray(position, chunk, 0, (int)bytesToRead);
					if (bytesRead == 0 || !processChunk(chunk, bytesRead))
						break;
					position += bytesRead;
				}
			}
			finally
			{
				ArrayPool<byte>.Shared.Return(chunk);
			}
		}

		public bool IsBinaryFile()
		{
			var isBinaryFile = false;
			fileInfo.ReadBytesChunkedMemoryMapped((chunk, bytesRead) =>
			{
				for (var i = 0; i < bytesRead; ++i)
				{
					var b = chunk[i];
					// Null byte indicates binary
					if (b == 0)
					{
						isBinaryFile = true;
						return false;
					}
					// Non-text control characters (0-31 except \t, \n, \r)
					if (b < 32 && b != 9 && b != 10 && b != 13)
					{
						isBinaryFile = true;
						return false;
					}
				}
				//return true; // proceed
				// Cut it short after the first chunk and call it non-binary... (return false)
				return false;
			});
			return isBinaryFile;
		}
	}
}

// Helper class for creating directory junctions (works without admin on Windows)
internal sealed class JunctionPoint
{
	private readonly string _junctionPath;
	private readonly string _targetPath;

	public JunctionPoint(string junctionPath, string targetPath)
	{
		_junctionPath = junctionPath;
		_targetPath = Path.GetFullPath(targetPath);
	}

	public void Create()
	{
		//if (OperatingSystem.IsWindows())
		//{
		//	CreateWindowsJunction();
		//}
		//else
		{
			// On non-Windows, use symbolic link
			Directory.CreateSymbolicLink(_junctionPath, _targetPath);
		}
	}

	private void CreateWindowsJunction()
	{
		// First try P/Invoke method
		try
		{
			CreateWindowsJunctionInternal();
			return;
		}
		catch
		{
			// Fallback to cmd.exe mklink /J
		}

		// Fallback: use cmd.exe /c mklink /J (junction, not /D which requires admin)
		var psi = new ProcessStartInfo
		{
			FileName = "cmd.exe",
			RedirectStandardOutput = true,
			RedirectStandardError = true,
			UseShellExecute = false,
			CreateNoWindow = true
		};
		// Use ArgumentList instead of Arguments for proper escaping
		psi.ArgumentList.Add("/c");
		psi.ArgumentList.Add("mklink");
		psi.ArgumentList.Add("/J");
		psi.ArgumentList.Add(_junctionPath);
		psi.ArgumentList.Add(_targetPath);
		using var process = Process.Start(psi);
		if (process is null)
		{
			throw new IOException("Failed to start cmd.exe for mklink");
		}
		process.WaitForExit();
		if (process.ExitCode != 0)
		{
			var stderr = process.StandardError.ReadToEnd();
			throw new IOException($"mklink failed: {stderr}");
		}
	}

	private void CreateWindowsJunctionInternal()
	{
		// Create the junction directory first
		Directory.CreateDirectory(_junctionPath);

		// Use P/Invoke to create junction
		using var handle = CreateFile(
			_junctionPath,
			0x40000000, // GENERIC_WRITE
			0,
			IntPtr.Zero,
			3, // OPEN_EXISTING
			0x2000000 | 0x02000000, // FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT
			IntPtr.Zero);

		if (handle.IsInvalid)
		{
			throw new IOException("Failed to open junction directory");
		}

		// Create reparse point data
		var target = Path.GetFullPath(_targetPath);
		if (!target.StartsWith("\\\\?\\"))
		{
			target = "\\\\?\\" + target;
		}
		var targetBytes = Encoding.Unicode.GetBytes(target);
		var pathBytes = new byte[targetBytes.Length + 12];
		// Header
		BitConverter.GetBytes((uint)0xA0000003).CopyTo(pathBytes, 0); // ReparseTag = IO_REPARSE_TAG_MOUNT_POINT
		BitConverter.GetBytes((ushort)(targetBytes.Length + 8 + 2)).CopyTo(pathBytes, 4); // ReparseDataLength
		BitConverter.GetBytes((ushort)0).CopyTo(pathBytes, 6); // Reserved
		BitConverter.GetBytes((ushort)(targetBytes.Length)).CopyTo(pathBytes, 8); // SubstituteNameOffset
		BitConverter.GetBytes((ushort)(targetBytes.Length)).CopyTo(pathBytes, 10); // SubstituteNameLength
		BitConverter.GetBytes((ushort)0).CopyTo(pathBytes, 12); // PrintNameOffset
		BitConverter.GetBytes((ushort)0).CopyTo(pathBytes, 14); // PrintNameLength
		targetBytes.CopyTo(pathBytes, 16);

		if (!DeviceIoControl(handle.DangerousGetHandle(), 0x900A4, pathBytes, pathBytes.Length, null, 0, out _,
				IntPtr.Zero))
		{
			throw new IOException("Failed to create junction point");
		}
	}

	[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
	private static extern SafeFileHandle CreateFile(
		string lpFileName,
		uint dwDesiredAccess,
		uint dwShareMode,
		IntPtr lpSecurityAttributes,
		uint dwCreationDisposition,
		uint dwFlagsAndAttributes,
		IntPtr hTemplateFile);

	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool DeviceIoControl(
		IntPtr hDevice,
		uint dwIoControlCode,
		byte[] lpInBuffer,
		int nInBufferSize,
		byte[]? lpOutBuffer,
		int nOutBufferSize,
		out int lpBytesReturned,
		IntPtr lpOverlapped);
}
