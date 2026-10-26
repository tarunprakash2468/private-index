import {
  Action,
  ActionPanel,
  Color,
  getPreferenceValues,
  Icon,
  List,
  openExtensionPreferences,
  showToast,
  Toast,
} from "@raycast/api";
import { execFile, ChildProcess } from "child_process";
import fs from "fs";
import path from "path";
import os from "os";
import { useEffect, useState, useRef, useMemo } from "react";

export interface SearchResult {
  id: number;
  filePath: string;
  fileName: string;
  matchType: "hybrid" | "vector" | "keyword" | string;
  score: number;
  confidence: number;
  distance: number;
  snippet: string;
  mtime: number;
}

export interface Preferences {
  executablePath?: string;
  searchMode?: "hybrid" | "vector" | "keyword";
  minSimilarity?: string;
  resultLimit?: string;
}

export function resolveExecutablePath(customPath?: string): string | null {
  if (customPath && customPath.trim().length > 0) {
    let expanded = customPath.trim();
    if (expanded.startsWith("~")) {
      expanded = path.join(os.homedir(), expanded.slice(1));
    }
    if (fs.existsSync(expanded)) {
      try {
        fs.accessSync(expanded, fs.constants.X_OK);
        return expanded;
      } catch {
        // Not executable
      }
    }
  }

  const candidates = [
    "/opt/homebrew/bin/pi",
    "/usr/local/bin/pi",
    "/usr/bin/pi",
    path.join(os.homedir(), ".cargo/bin/pi"),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      try {
        fs.accessSync(candidate, fs.constants.X_OK);
        return candidate;
      } catch {
        // Continue searching
      }
    }
  }

  const pathEnv = process.env.PATH || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
  const pathDirs = pathEnv.split(":");
  for (const dir of pathDirs) {
    const candidate = path.join(dir, "pi");
    if (fs.existsSync(candidate)) {
      try {
        fs.accessSync(candidate, fs.constants.X_OK);
        return candidate;
      } catch {
        // Continue searching
      }
    }
  }

  return null;
}

function formatBytes(bytes: number): string {
  if (bytes <= 0 || isNaN(bytes)) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function getFileSize(filePath: string): string {
  try {
    if (fs.existsSync(filePath)) {
      const stats = fs.statSync(filePath);
      return formatBytes(stats.size);
    }
  } catch {
    // Ignore error
  }
  return "Unknown";
}

function formatDate(timestampInSec: number, filePath: string): string {
  let date: Date | null = null;
  if (timestampInSec && timestampInSec > 0) {
    date = new Date(timestampInSec * 1000);
  } else {
    try {
      if (fs.existsSync(filePath)) {
        const stats = fs.statSync(filePath);
        date = stats.mtime;
      }
    } catch {
      // Ignore error
    }
  }

  if (!date || isNaN(date.getTime())) return "Unknown";

  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function getConfidenceColor(confidence: number): Color | string {
  if (confidence >= 90) {
    return Color.Green;
  } else if (confidence >= 75) {
    return "#20b2aa"; // Teal
  } else {
    return Color.Yellow;
  }
}

function getMatchTypeColor(matchType: string): Color {
  switch (matchType.toLowerCase()) {
    case "hybrid":
      return Color.Green;
    case "vector":
      return Color.Blue;
    case "keyword":
      return Color.Orange;
    default:
      return Color.SecondaryText;
  }
}

function buildDetailMarkdown(item: SearchResult): string {
  const cleanSnippet = item.snippet.trim();
  const quotedSnippet = cleanSnippet
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");

  return `### ${item.fileName}\n\n${quotedSnippet}`;
}

function formatDisplayPath(fullPath: string): string {
  const home = os.homedir();
  const dir = path.dirname(fullPath);
  if (dir.startsWith(home)) {
    return `~${dir.slice(home.length)}`;
  }
  return dir;
}

export default function SearchCommand() {
  const preferences = useMemo(() => getPreferenceValues<Preferences>(), []);
  const [searchText, setSearchText] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [missingBinary, setMissingBinary] = useState(false);

  const searchIdRef = useRef(0);
  const activeProcessRef = useRef<ChildProcess | null>(null);

  useEffect(() => {
    const trimmed = searchText.trim();
    if (!trimmed) {
      setResults([]);
      setIsLoading(false);
      setError(null);
      return;
    }

    const execPath = resolveExecutablePath(preferences.executablePath);
    if (!execPath) {
      setMissingBinary(true);
      setIsLoading(false);
      showToast({
        style: Toast.Style.Failure,
        title: "Private Index CLI Not Found",
        message: "Run `brew install tarunprakash2468/private-index/private-index`",
      });
      return;
    }
    setMissingBinary(false);

    const searchId = ++searchIdRef.current;
    setIsLoading(true);
    setError(null);

    if (activeProcessRef.current) {
      try {
        activeProcessRef.current.kill();
      } catch {
        // Process already terminated
      }
      activeProcessRef.current = null;
    }

    const mode = preferences.searchMode || "hybrid";
    const limit = preferences.resultLimit || "15";
    const minSimilarity = preferences.minSimilarity || "35%";

    const args = [
      "search",
      trimmed,
      "--json",
      "--mode",
      mode,
      "--limit",
      limit,
      "--min-similarity",
      minSimilarity,
    ];

    const child = execFile(
      execPath,
      args,
      { maxBuffer: 10 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (searchId !== searchIdRef.current) {
          return;
        }

        setIsLoading(false);

        if (err) {
          if (child.killed) return;
          const raw = stderr.trim() || stdout.trim() || err.message;
          let errMsg = raw;
          try {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed.error === "string") {
              errMsg = parsed.error;
            }
          } catch {
            // Raw text error
          }
          setError(errMsg);
          setResults([]);
          return;
        }

        try {
          const parsed = JSON.parse(stdout || "[]");
          if (Array.isArray(parsed)) {
            setResults(parsed);
            setError(null);
          } else {
            setResults([]);
          }
        } catch (parseErr: unknown) {
          const msg = parseErr instanceof Error ? parseErr.message : String(parseErr);
          setError(`Failed to parse search results: ${msg}`);
          setResults([]);
        }
      }
    );

    activeProcessRef.current = child;

    return () => {
      if (activeProcessRef.current === child) {
        try {
          child.kill();
        } catch {
          // Process already terminated
        }
      }
    };
  }, [
    searchText,
    preferences.executablePath,
    preferences.searchMode,
    preferences.resultLimit,
    preferences.minSimilarity,
  ]);

  if (missingBinary) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.Warning}
          title="Private Index CLI Not Found"
          description="Could not locate the `pi` executable. Install it via Homebrew:&#10;&#10;brew install tarunprakash2468/private-index/private-index"
          actions={
            <ActionPanel>
              <Action.CopyToClipboard
                title="Copy Homebrew Command"
                content="brew install tarunprakash2468/private-index/private-index"
              />
              <Action.OpenInBrowser
                title="Open GitHub Repository"
                url="https://github.com/tarunprakash2468/private-index"
              />
              <Action
                title="Open Extension Preferences"
                icon={Icon.Gear}
                onAction={openExtensionPreferences}
              />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  const isDatabaseNotFoundError =
    error &&
    (error.toLowerCase().includes("database not found") ||
      error.toLowerCase().includes("haven't indexed") ||
      error.toLowerCase().includes("please run `pi index"));

  return (
    <List
      isShowingDetail={results.length > 0}
      isLoading={isLoading}
      onSearchTextChange={setSearchText}
      throttle
      searchBarPlaceholder="Search documents semantically (e.g., salary, roadmap, taxes)..."
    >
      {isDatabaseNotFoundError ? (
        <List.EmptyView
          icon={Icon.Folder}
          title="No Documents Indexed Yet"
          description="Your Private Index database has not been initialized.&#10;&#10;Run `pi index <directory>` in Terminal to scan and index a folder for on-device semantic search."
          actions={
            <ActionPanel>
              <Action.CopyToClipboard
                title="Copy Index Command"
                content="pi index ~/Documents"
              />
              <Action.CopyToClipboard
                title="Copy Watch Daemon Command"
                content="pi watch ~/Documents --install-launchagent"
              />
              <Action
                title="Open Extension Preferences"
                icon={Icon.Gear}
                onAction={openExtensionPreferences}
              />
            </ActionPanel>
          }
        />
      ) : error ? (
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="Search Failed"
          description={error}
          actions={
            <ActionPanel>
              <Action
                title="Open Extension Preferences"
                icon={Icon.Gear}
                onAction={openExtensionPreferences}
              />
              <Action.CopyToClipboard
                title="Copy Error Message"
                content={error}
              />
            </ActionPanel>
          }
        />
      ) : searchText.trim().length > 0 && results.length === 0 && !isLoading ? (
        <List.EmptyView
          icon={Icon.MagnifyingGlass}
          title="No Matches Found"
          description={`No results found for "${searchText}".&#10;&#10;Suggestions:&#10;• Try a broader query or alternative keywords&#10;• Lower the similarity threshold in preferences (current: ${preferences.minSimilarity || "35%"})&#10;• Switch search mode to keyword or hybrid`}
          actions={
            <ActionPanel>
              <Action
                title="Open Extension Preferences"
                icon={Icon.Gear}
                onAction={openExtensionPreferences}
              />
              <Action.CopyToClipboard
                title="Copy Current Query"
                content={searchText}
              />
            </ActionPanel>
          }
        />
      ) : (
        <List.EmptyView
          icon={Icon.Document}
          title="Search Private Index"
          description="Search local documents, notes, and PDFs semantically using on-device AI.&#10;&#10;Start typing to search across your indexed documents."
          actions={
            <ActionPanel>
              <Action.CopyToClipboard
                title="Copy Index Command"
                content="pi index ~/Documents"
              />
              <Action
                title="Open Extension Preferences"
                icon={Icon.Gear}
                onAction={openExtensionPreferences}
              />
            </ActionPanel>
          }
        />
      )}

      {results.map((item) => {
        const confidenceColor = getConfidenceColor(item.confidence);
        const matchTypeColor = getMatchTypeColor(item.matchType);
        const displayParent = formatDisplayPath(item.filePath);

        return (
          <List.Item
            key={`${item.id}-${item.filePath}`}
            title={item.fileName}
            subtitle={displayParent}
            icon={{ fileIcon: item.filePath }}
            quickLook={{ path: item.filePath, name: item.fileName }}
            accessories={[
              {
                tag: {
                  value: `[${item.matchType}]`,
                  color: matchTypeColor,
                },
                tooltip: `Match Mode: ${item.matchType}`,
              },
              {
                tag: {
                  value: `${item.confidence}% match`,
                  color: confidenceColor,
                },
                tooltip: `Confidence: ${item.confidence}% (Score: ${(item.score * 100).toFixed(1)}%)`,
              },
            ]}
            detail={
              <List.Item.Detail
                markdown={buildDetailMarkdown(item)}
                metadata={
                  <List.Item.Detail.Metadata>
                    <List.Item.Detail.Metadata.Label
                      title="File Name"
                      text={item.fileName}
                      icon={{ fileIcon: item.filePath }}
                    />
                    <List.Item.Detail.Metadata.Label
                      title="File Path"
                      text={item.filePath}
                    />
                    <List.Item.Detail.Metadata.Label
                      title="File Size"
                      text={getFileSize(item.filePath)}
                    />
                    <List.Item.Detail.Metadata.Label
                      title="Last Modified"
                      text={formatDate(item.mtime, item.filePath)}
                    />
                    <List.Item.Detail.Metadata.Separator />
                    <List.Item.Detail.Metadata.TagList title="Match Score">
                      <List.Item.Detail.Metadata.TagList.Item
                        text={`${item.confidence}% match`}
                        color={confidenceColor}
                      />
                      <List.Item.Detail.Metadata.TagList.Item
                        text={`[${item.matchType}]`}
                        color={matchTypeColor}
                      />
                    </List.Item.Detail.Metadata.TagList>
                    <List.Item.Detail.Metadata.Label
                      title="Raw Score"
                      text={(item.score * 100).toFixed(2) + "%"}
                    />
                    <List.Item.Detail.Metadata.Label
                      title="Vector Distance"
                      text={item.distance.toFixed(4)}
                    />
                  </List.Item.Detail.Metadata>
                }
              />
            }
            actions={
              <ActionPanel>
                <Action.Open
                  title="Open File"
                  target={item.filePath}
                />
                <Action.ShowInFinder
                  title="Reveal in Finder"
                  path={item.filePath}
                />
                <Action.ToggleQuickLook
                  title="Quick Look"
                />
                <Action.CopyToClipboard
                  title="Copy Snippet"
                  content={item.snippet}
                  shortcut={{ modifiers: ["cmd"], key: "c" }}
                />
                <Action.CopyToClipboard
                  title="Copy File Path"
                  content={item.filePath}
                  shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
                />
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}
