// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

//#define JSON_USE_SNAKE_CASE

// TODO: Use C# records instead of classes... and perhaps go into preview C# 15 and use unions...

// TODO: Add models for these (for completeness):
// - api.nanos-world.com/tags
// - api.nanos-world.com/user/teams
// - api.nanos-world.com/store/assets?page_size=100

namespace NanosWorld;

#if JSON_USE_SNAKE_CASE
public sealed partial class Packages
{
	public string message { get; set; }
	public string? request_id { get; set; }
	public Payload? payload { get; set; }

	public sealed class Payload
	{
		public Package.Payload[]? packages { get; set; }
		public UInt128 total { get; set; }
		public UInt128 page { get; set; }
		public UInt128 page_size { get; set; }
		public Filters filters { get; set; }
	}

	public sealed class Filters
	{
		public Tag[]? tags { get; set; }
		public string sort_by { get; set; }
		public string sort_order { get; set; }
	}
}

public sealed partial class Package
{
	public string message { get; set; }
	public string? request_id { get; set; }
	public Payload? payload { get; set; }

	public sealed class Payload
	{
		public Guid id { get; set; }
		public Guid user_id { get; set; }
		public string name { get; set; }
		public string description { get; set; }
		public string short_description { get; set; }
		public string title { get; set; }
		public string type { get; set; }
		public Uri? icon_url { get; set; }
		public Uri? cover_url { get; set; }
		public Image[]? images { get; set; }
		public Uri? github_url { get; set; }
		public UInt128 download_count { get; set; }
		public UInt128 view_count { get; set; }
		public Uri? download_url { get; set; }
		public bool published { get; set; }
		public Ratings ratings { get; set; }
		public dynamic links { get; set; }
		public Tag[] tags { get; set; }
		public Guid team_id { get; set; }
		public Team team { get; set; }
		public Version? version { get; set; }
		public Version[]? package_versions { get; set; }
		public DateTimeOffset created_at { get; set; }
		public DateTimeOffset updated_at { get; set; }
		public decimal? price_in_cents { get; set; }
	}
}

public sealed class Image
{
	public Uri image_url { get; set; }
	public Int128 image_index { get; set; }
}

public sealed class Version
{
	public Guid id { get; set; }
	public Guid package_id { get; set; }
	public string version { get; set; }
	public string status { get; set; }
	public string changelog { get; set; }
	public DateTimeOffset? validated_at { get; set; }
	public DateTimeOffset upload_date { get; set; }
	public Uri? download_url { get; set; }
	public Int128 zip_size_bytes { get; set; }
	public Int128 extracted_size_bytes { get; set; }
	public string parsed_author { get; set; }
	public DateTimeOffset created_at { get; set; }
	public DateTimeOffset updated_at { get; set; }
	public Uri toml_url { get; set; }
	public GameMode? game_mode { get; set; }
	public Map? map { get; set; }
	public Script? script { get; set; }
}

public sealed class GameMode
{
	public bool force_no_map_package { get; set; }
	public bool auto_cleanup { get; set; }
	public bool load_level_entities { get; set; }
	public string compatibility_version { get; set; }
	public string[]? package_requirements { get; set; }
	public string[]? assets_requirements { get; set; }
	public string[]? compatible_maps { get; set; }
	public dynamic custom_settings { get; set; }
}

public sealed class CustomSettings;

public sealed class Map
{
	public bool auto_cleanup { get; set; }
	public bool load_level_entities { get; set; }
	public string compatibility_version { get; set; }
	public string[]? package_requirements { get; set; }
	public string[]? assets_requirements { get; set; }
	public string[]? compatible_game_modes { get; set; }
	public string map_asset { get; set; }
	public dynamic custom_data { get; set; }
}

public sealed class CustomData;

public sealed class Script
{
	public bool force_no_map_package { get; set; }
	public bool auto_cleanup { get; set; }
	public bool load_level_entities { get; set; }
	public string compatibility_version { get; set; }
	public string[]? package_requirements { get; set; }
	public string[]? assets_requirements { get; set; }
	public string[]? compatible_maps { get; set; }
}

public sealed class Ratings
{
	public UInt128 total { get; set; }
	public decimal average { get; set; }
	public UInt128 one_star { get; set; }
	public UInt128 two_star { get; set; }
	public UInt128 three_star { get; set; }
	public UInt128 four_star { get; set; }
	public UInt128 five_star { get; set; }
}

public sealed class Tag
{
	public Guid id { get; set; }
	public DateTimeOffset created_at { get; set; }
	public DateTimeOffset updated_at { get; set; }
	public DateTimeOffset? deleted_at { get; set; }
	public string name { get; set; }
	public string slug { get; set; }
	public string description { get; set; }
	public string color { get; set; }
	public string icon { get; set; }
	public UInt128 usage_count { get; set; }
}

public sealed class Team
{
	public Guid id { get; set; }
	public string name { get; set; }
	public string description { get; set; }
	public Uri? icon_url { get; set; }
}

public sealed class PresignResponse
{
	public string message { get; set; }
	public string? request_id { get; set; }
	public Payload? payload { get; set; }

	public sealed class Payload
	{
		public Uri? presigned_url { get; set; }
		public Uri? url { get; set; }
		public string filename { get; set; }
	}
}
#else
// @formatter:off
public sealed partial class Packages
{
	[J("message")]    public string Message { get; set; }
	[J("request_id")] public string? RequestId { get; set; }
	[J("payload")]    public Payload? payload { get; set; }

	public sealed class Payload
	{
		[J("packages")]  public Package.Payload[]? Packages { get; set; }
		[J("total")]     public UInt128 Total { get; set; }
		[J("page")]      public UInt128 Page { get; set; }
		[J("page_size")] public UInt128 PageSize { get; set; }
		[J("filters")]   public Filters Filters { get; set; }
	}

	public sealed class Filters
	{
		[J("tags")]       public Tag[]? Tags { get; set; } // NOTE: guessed type (ask Syed)
		[J("sort_by")]    public string SortBy { get; set; }
		[J("sort_order")] public string SortOrder { get; set; }
	}
}

public sealed partial class Package
{
	[J("message")]    public string Message { get; set; }
	[J("request_id")] public string? RequestId { get; set; }
	[J("payload")]    public Payload? payload { get; set; }

	public sealed class Payload
	{
		[J("id")]                public Guid Id { get; set; }
		[J("user_id")]           public Guid UserId { get; set; }
		[J("name")]              public string Name { get; set; }
		[J("description")]       public string Description { get; set; }
		[J("short_description")] public string ShortDescription { get; set; }
		[J("title")]             public string Title { get; set; }
		[J("type")]              public string Type { get; set; }
		[J("icon_url")]          public Uri? IconUrl { get; set; }
		[J("cover_url")]         public Uri? CoverUrl { get; set; }
		[J("images")]            public Image[]? Images { get; set; }
		[J("github_url")]        public Uri? GithubUrl { get; set; }
		[J("download_count")]    public UInt128 DownloadCount { get; set; }
		[J("view_count")]        public UInt128 ViewCount { get; set; }
		[J("download_url")]      public Uri? DownloadUrl { get; set; }
		[J("published")]         public bool Published { get; set; }
		[J("ratings")]           public Ratings Ratings { get; set; }
		[J("links")]             public dynamic Links { get; set; } // TODO: Ask Syed ... Uri[] ?
		[J("tags")]              public Tag[] Tags { get; set; }
		[J("team_id")]           public Guid TeamId { get; set; }
		[J("team")]              public Team Team { get; set; }
		[J("version")]           public Version? Version { get; set; }
		[J("package_versions")]  public Version[]? PackageVersions { get; set; }
		[J("created_at")]        public DateTimeOffset CreatedAt { get; set; }
		[J("updated_at")]        public DateTimeOffset UpdatedAt { get; set; }
		[J("price_in_cents")]    public decimal? PriceInCents { get; set; }
	}
}

public sealed class Image
{
	[J("image_url")]   public Uri ImageUrl { get; set; }
	[J("image_index")] public Int128 ImageIndex { get; set; }
}

public sealed class Version
{
	[J("id")]                   public Guid Id { get; set; }
	[J("package_id")]           public Guid PackageId { get; set; }
	[J("version")]              public string VersionString { get; set; }
	[J("status")]               public string Status { get; set; }
	[J("changelog")]            public string Changelog { get; set; }
	[J("validated_at")]         public DateTimeOffset? ValidatedAt { get; set; }
	[J("upload_date")]          public DateTimeOffset UploadDate { get; set; }
	[J("download_url")]         public Uri? DownloadUrl { get; set; }
	[J("zip_size_bytes")]       public Int128 ZipSizeBytes { get; set; } // TODO/CONS: Use UInt128
	[J("extracted_size_bytes")] public Int128 ExtractedSizeBytes { get; set; } // TODO/CONS: Use UInt128
	[J("parsed_author")]        public string ParsedAuthor { get; set; }
	[J("created_at")]           public DateTimeOffset CreatedAt { get; set; }
	[J("updated_at")]           public DateTimeOffset UpdatedAt { get; set; }
	[J("toml_url")]             public Uri TomlUrl { get; set; }
	[J("game_mode")]            public GameMode? GameMode { get; set; }
	[J("map")]                  public Map? Map { get; set; }
	[J("script")]               public Script? Script { get; set; }
}

public sealed class GameMode
{
	[J("force_no_map_package")]  public bool ForceNoMapPackage { get; set; }
	[J("auto_cleanup")]          public bool AutoCleanup { get; set; }
	[J("load_level_entities")]   public bool LoadLevelEntities { get; set; }
	[J("compatibility_version")] public string CompatibilityVersion { get; set; }
	[J("package_requirements")]  public string[]? PackageRequirements { get; set; }
	[J("assets_requirements")]   public string[]? AssetsRequirements { get; set; }
	[J("compatible_maps")]       public string[]? CompatibleMaps { get; set; }
	[J("custom_settings")]       public dynamic CustomSettings { get; set; } // TODO/CONS: CustomSettings?
}

public sealed class CustomSettings;

public sealed class Map
{
	[J("auto_cleanup")]          public bool AutoCleanup { get; set; }
	[J("load_level_entities")]   public bool LoadLevelEntities { get; set; }
	[J("compatibility_version")] public string CompatibilityVersion { get; set; }
	[J("package_requirements")]  public string[]? PackageRequirements { get; set; }
	[J("assets_requirements")]   public string[]? AssetsRequirements { get; set; }
	[J("compatible_game_modes")] public string[]? CompatibleGameModes { get; set; }
	[J("map_asset")]             public string MapAsset { get; set; }
	[J("custom_data")]           public dynamic CustomData { get; set; } // TODO/CONS: CustomData?
}

public sealed class CustomData;

public sealed class Script
{
	[J("force_no_map_package")]  public bool ForceNoMapPackage { get; set; }
	[J("auto_cleanup")]          public bool AutoCleanup { get; set; }
	[J("load_level_entities")]   public bool LoadLevelEntities { get; set; }
	[J("compatibility_version")] public string CompatibilityVersion { get; set; }
	[J("package_requirements")]  public string[]? PackageRequirements { get; set; } // NOTE: guessed type (ask Syed)
	[J("assets_requirements")]   public string[]? AssetsRequirements { get; set; } // NOTE: guessed type (ask Syed)
	[J("compatible_maps")]       public string[]? CompatibleMaps { get; set; } // NOTE: guessed type (ask Syed)
}

public sealed class Ratings
{
	[J("total")]      public UInt128 Total { get; set; }
	[J("average")]    public decimal Average { get; set; }
	[J("one_star")]   public UInt128 OneStar { get; set; }
	[J("two_star")]   public UInt128 TwoStar { get; set; }
	[J("three_star")] public UInt128 ThreeStar { get; set; }
	[J("four_star")]  public UInt128 FourStar { get; set; }
	[J("five_star")]  public UInt128 FiveStar { get; set; }
}

public sealed class Tag
{
	[J("id")]          public Guid Id { get; set; }
	[J("created_at")]  public DateTimeOffset CreatedAt { get; set; }
	[J("updated_at")]  public DateTimeOffset UpdatedAt { get; set; }
	[J("deleted_at")]  public DateTimeOffset? DeletedAt { get; set; } // NOTE: guessed type (ask Syed)
	[J("name")]        public string Name { get; set; }
	[J("slug")]        public string Slug { get; set; }
	[J("description")] public string Description { get; set; }
	[J("color")]       public string Color { get; set; }
	[J("icon")]        public string Icon { get; set; }
	[J("usage_count")] public UInt128 UsageCount { get; set; }
}

public sealed class Team
{
	[J("id")]          public Guid Id { get; set; }
	[J("name")]        public string Name { get; set; }
	[J("description")] public string Description { get; set; }
	[J("icon_url")]    public Uri? IconUrl { get; set; }
}

public sealed class PresignResponse
{
	[J("message")]    public string Message { get; set; }
	[J("request_id")] public string? RequestId { get; set; }
	[J("payload")]    public Payload? payload { get; set; }

	public sealed class Payload
	{
		[J("presigned_url")] public Uri? PresignedUrl { get; set; }
		[J("url")]           public Uri? Url { get; set; }
		[J("filename")]      public string FileName { get; set; }
	}
}
// @formatter:on
#endif

public sealed partial class Packages
{
	public static Packages? FromJson(string json) =>
		JsonSerializer.Deserialize<Packages>(json, JsonOptions.Instance);

	public string ToJson() =>
		JsonSerializer.Serialize(this, JsonOptions.Instance);
}

public sealed partial class Package
{
	public static Package? FromJson(string json) =>
		JsonSerializer.Deserialize<Package>(json, JsonOptions.Instance);

	public string ToJson() =>
		JsonSerializer.Serialize(this, JsonOptions.Instance);
}

internal static class JsonOptions
{
	public static readonly JsonSerializerOptions Instance = new()
	{
		AllowDuplicateProperties = true,
		AllowTrailingCommas = true,
		IgnoreReadOnlyFields = true,
		IgnoreReadOnlyProperties = true,
		IncludeFields = false,
		PropertyNameCaseInsensitive = true,
		PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
		IndentCharacter = ' ',
		IndentSize = 2,
		NewLine = "\n",
		WriteIndented = true,
		NumberHandling = JsonNumberHandling.AllowReadingFromString,
		ReadCommentHandling = JsonCommentHandling.Skip,
		RespectNullableAnnotations = false,
		RespectRequiredConstructorParameters = false,
		UnknownTypeHandling = JsonUnknownTypeHandling.JsonNode,
		UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
		Converters =
		{
			DateOnlyConverter.Singleton,
			TimeOnlyConverter.Singleton,
			IsoDateTimeOffsetConverter.Singleton
		},
	};
}

internal sealed class DateOnlyConverter : JsonConverter<DateOnly>
{
	private readonly string serializationFormat;

	public DateOnlyConverter() : this(null) { }

	public DateOnlyConverter(string? serializationFormat)
	{
		this.serializationFormat = serializationFormat ?? "yyyy-MM-dd";
	}

	public override DateOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
	{
		var value = reader.GetString();
		return DateOnly.Parse(value!);
	}

	public override void Write(Utf8JsonWriter writer, DateOnly value, JsonSerializerOptions options) =>
		writer.WriteStringValue(value.ToString(serializationFormat));

	public static readonly DateOnlyConverter Singleton = new();
}

internal sealed class TimeOnlyConverter : JsonConverter<TimeOnly>
{
	private readonly string serializationFormat;

	public TimeOnlyConverter() : this(null) { }

	public TimeOnlyConverter(string? serializationFormat)
	{
		this.serializationFormat = serializationFormat ?? "HH:mm:ss.fff";
	}

	public override TimeOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
	{
		var value = reader.GetString();
		return TimeOnly.Parse(value!);
	}

	public override void Write(Utf8JsonWriter writer, TimeOnly value, JsonSerializerOptions options) =>
		writer.WriteStringValue(value.ToString(serializationFormat));

	public static readonly TimeOnlyConverter Singleton = new();
}

internal sealed class IsoDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
{
	public override bool CanConvert(Type t) => t == typeof(DateTimeOffset);

	private const string DefaultDateTimeFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.FFFFFFFK";

	private DateTimeStyles _dateTimeStyles = DateTimeStyles.RoundtripKind;
	private string? _dateTimeFormat;
	private CultureInfo? _culture;

	public DateTimeStyles DateTimeStyles
	{
		get => _dateTimeStyles;
		set => _dateTimeStyles = value;
	}

	public string? DateTimeFormat
	{
		get => _dateTimeFormat ?? string.Empty;
		set => _dateTimeFormat = (string.IsNullOrEmpty(value)) ? null : value;
	}

	public CultureInfo Culture
	{
		get => _culture ?? CultureInfo.CurrentCulture;
		set => _culture = value;
	}

	public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
	{
		if ((_dateTimeStyles & DateTimeStyles.AdjustToUniversal) == DateTimeStyles.AdjustToUniversal
			|| (_dateTimeStyles & DateTimeStyles.AssumeUniversal) == DateTimeStyles.AssumeUniversal)
		{
			value = value.ToUniversalTime();
		}
		var text = value.ToString(_dateTimeFormat ?? DefaultDateTimeFormat, Culture);
		writer.WriteStringValue(text);
	}

	public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
	{
		var dateText = reader.GetString();
		if (string.IsNullOrEmpty(dateText) == false)
		{
			if (!string.IsNullOrEmpty(_dateTimeFormat))
			{
				return DateTimeOffset.ParseExact(dateText, _dateTimeFormat, Culture, _dateTimeStyles);
			}
			return DateTimeOffset.Parse(dateText, Culture, _dateTimeStyles);
		}
		return default;
	}

	public static readonly IsoDateTimeOffsetConverter Singleton = new();
}
