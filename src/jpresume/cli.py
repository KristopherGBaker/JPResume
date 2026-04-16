"""CLI entry point for jpresume."""

import argparse
import sys
from pathlib import Path

from jpresume import __version__


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jpresume",
        description="Convert western-style resumes to Japanese format (履歴書・職務経歴書)",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # convert command
    convert_parser = subparsers.add_parser(
        "convert", help="Convert a western resume to Japanese format"
    )
    convert_parser.add_argument("input", type=Path, help="Path to western-style markdown resume")
    convert_parser.add_argument(
        "-o", "--output-dir", type=Path, default=None,
        help="Output directory (default: same as input file)",
    )
    convert_parser.add_argument(
        "-c", "--config", type=Path, default=None,
        help="Path to YAML config file (default: {input_dir}/jpresume_config.yaml)",
    )
    convert_parser.add_argument(
        "--reconfigure", action="store_true",
        help="Re-prompt for all Japan-specific fields",
    )
    convert_parser.add_argument(
        "--format", choices=["markdown", "pdf", "both"], default="both",
        help="Output format (default: both)",
    )
    convert_parser.add_argument(
        "--rirekisho-only", action="store_true",
        help="Generate only the rirekisho (履歴書)",
    )
    convert_parser.add_argument(
        "--shokumukeirekisho-only", action="store_true",
        help="Generate only the shokumukeirekisho (職務経歴書)",
    )
    convert_parser.add_argument(
        "--provider",
        choices=["anthropic", "openai", "openrouter", "ollama", "claude-cli", "codex-cli"],
        default="ollama",
        help="AI provider (default: ollama)",
    )
    convert_parser.add_argument(
        "--model", default=None,
        help="Model name override (default: provider-specific default)",
    )
    convert_parser.add_argument(
        "--era", choices=["western", "japanese"], default="western",
        help="Date format style (default: western, e.g. 2024年3月)",
    )
    convert_parser.add_argument(
        "--no-cache", action="store_true",
        help="Ignore cached AI output and regenerate",
    )
    convert_parser.add_argument(
        "--dry-run", action="store_true",
        help="Parse and analyze only, don't generate output",
    )
    convert_parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Show detailed output including AI prompts/responses",
    )

    return parser


def cmd_convert(args: argparse.Namespace) -> None:
    """Execute the convert command."""
    from rich.console import Console

    from jpresume.ai import ResumeAI
    from jpresume.config import load_or_prompt_config
    from jpresume.models import RirekishoData, ShokumukeirekishoData
    from jpresume.parser import parse_resume
    from jpresume.render import render_rirekisho, render_shokumukeirekisho

    console = Console()

    # Validate input
    if not args.input.exists():
        console.print(f"[red]Error:[/red] Input file not found: {args.input}")
        sys.exit(1)

    input_path = args.input.resolve()
    output_dir = (args.output_dir or input_path.parent).resolve()
    config_path = args.config or (input_path.parent / "jpresume_config.yaml")

    # Step 1: Parse western resume
    console.print("\n[bold]Step 1:[/bold] Parsing western resume...")
    resume_text = input_path.read_text(encoding="utf-8")
    western = parse_resume(resume_text)
    console.print(f"  Found: {len(western.experience)} work entries, "
                  f"{len(western.education)} education entries, "
                  f"{len(western.skills)} skills")

    if args.dry_run:
        console.print("\n[bold]Parsed resume data:[/bold]")
        console.print(western.model_dump_json(indent=2))
        console.print("\n[dim]Dry run complete. No output generated.[/dim]")
        return

    # Step 2: Load or gather Japan-specific config
    console.print("\n[bold]Step 2:[/bold] Gathering Japan-specific information...")
    japan_config = load_or_prompt_config(
        config_path, western, force_reconfigure=args.reconfigure
    )

    # Step 3: AI translation and adaptation
    generate_rirekisho = not args.shokumukeirekisho_only
    generate_shokumukeirekisho = not args.rirekisho_only

    rirekisho_data = None
    shokumukeirekisho_data = None

    # Check for cached AI output
    cache_dir = output_dir
    rirekisho_cache = cache_dir / ".rirekisho_cache.json"
    shokumu_cache = cache_dir / ".shokumukeirekisho_cache.json"

    import json

    if generate_rirekisho and rirekisho_cache.exists() and not args.no_cache:
        try:
            cached = json.loads(rirekisho_cache.read_text(encoding="utf-8"))
            rirekisho_data = RirekishoData.model_validate(cached)
            console.print("\n[bold]Step 3:[/bold] Using cached 履歴書 data "
                          f"([cyan]{rirekisho_cache}[/cyan])")
        except Exception:
            rirekisho_data = None  # Cache invalid, regenerate

    if generate_shokumukeirekisho and shokumu_cache.exists() and not args.no_cache:
        try:
            cached = json.loads(shokumu_cache.read_text(encoding="utf-8"))
            shokumukeirekisho_data = ShokumukeirekishoData.model_validate(cached)
            console.print("  Using cached 職務経歴書 data "
                          f"([cyan]{shokumu_cache}[/cyan])")
        except Exception:
            shokumukeirekisho_data = None

    needs_ai = ((generate_rirekisho and not rirekisho_data)
                or (generate_shokumukeirekisho and not shokumukeirekisho_data))

    if needs_ai:
        console.print("\n[bold]Step 3:[/bold] Translating and adapting with AI...")
        ai = ResumeAI(provider=args.provider, model=args.model, verbose=args.verbose)

        if generate_rirekisho and not rirekisho_data:
            with console.status("Generating 履歴書..."):
                rirekisho_data = ai.generate_rirekisho(western, japan_config, era=args.era)
            # Cache the result
            rirekisho_cache.write_text(
                rirekisho_data.model_dump_json(indent=2), encoding="utf-8"
            )
            console.print(f"  Cached to [dim]{rirekisho_cache}[/dim]")

        if generate_shokumukeirekisho and not shokumukeirekisho_data:
            with console.status("Generating 職務経歴書..."):
                shokumukeirekisho_data = ai.generate_shokumukeirekisho(
                    western, japan_config, era=args.era
                )
            # Cache the result
            shokumu_cache.write_text(
                shokumukeirekisho_data.model_dump_json(indent=2), encoding="utf-8"
            )
            console.print(f"  Cached to [dim]{shokumu_cache}[/dim]")

    # Step 4: Render output
    console.print("\n[bold]Step 4:[/bold] Generating output files...")
    output_dir.mkdir(parents=True, exist_ok=True)

    want_markdown = args.format in ("markdown", "both")
    want_pdf = args.format in ("pdf", "both")

    from jpresume.pdf import markdown_to_pdf
    from jpresume.pdf_rirekisho import render_rirekisho_pdf

    if rirekisho_data:
        if want_markdown:
            md_content = render_rirekisho(rirekisho_data)
            md_path = output_dir / "rirekisho.md"
            md_path.write_text(md_content, encoding="utf-8")
            console.print(f"  [green]✓[/green] {md_path}")
        if want_pdf:
            pdf_path = output_dir / "rirekisho.pdf"
            render_rirekisho_pdf(rirekisho_data, pdf_path)
            console.print(f"  [green]✓[/green] {pdf_path}")

    if shokumukeirekisho_data:
        if want_markdown:
            md_content = render_shokumukeirekisho(shokumukeirekisho_data)
            md_path = output_dir / "shokumukeirekisho.md"
            md_path.write_text(md_content, encoding="utf-8")
            console.print(f"  [green]✓[/green] {md_path}")
        if want_pdf:
            md_content = render_shokumukeirekisho(shokumukeirekisho_data)
            pdf_path = output_dir / "shokumukeirekisho.pdf"
            markdown_to_pdf(md_content, pdf_path)
            console.print(f"  [green]✓[/green] {pdf_path}")

    console.print("\n[bold green]Done![/bold green]")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    if args.command == "convert":
        cmd_convert(args)


if __name__ == "__main__":
    main()
