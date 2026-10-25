# Disable file completions for pi by default unless command handles it
complete -c pi -f
complete -c private-index -f
complete -c private-index-cli -f

# Commands and subcommands
for cmd in pi private-index private-index-cli
    complete -c $cmd -n "__fish_use_subcommand" -a index -d "Index documents in directory"
    complete -c $cmd -n "__fish_use_subcommand" -a search -d "Run semantic similarity search"
    complete -c $cmd -n "__fish_use_subcommand" -a stats -d "Show database statistics"
    complete -c $cmd -n "__fish_use_subcommand" -a reset -d "Clear database and purge vectors"
    complete -c $cmd -n "__fish_use_subcommand" -a help -d "Display help message"
    complete -c $cmd -s h -l help -d "Display help message"

    # Subcommand arguments
    complete -c $cmd -n "__fish_seen_subcommand_from index" -a "(__fish_complete_directories)" -d "Directory path"
    complete -c $cmd -n "__fish_seen_subcommand_from search" -l limit -d "Maximum search results"
end
