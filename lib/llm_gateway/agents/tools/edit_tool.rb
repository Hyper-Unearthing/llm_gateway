require "json"
require_relative "tool_utils"

class EditTool < LlmGateway::Tool
  # Pi adaptation notes:
  # - Legacy single-edit input: pi accepts oldText/newText and converts to edits,
  #   but this tool intentionally exposes/supports only the edits array to keep the LLM contract unambiguous.
  # - Do not add pi's diff/patch details, preview rendering, pluggable operations, or AbortSignal handling: those are UI/runtime extension concerns outside this tool contract.
  name "edit"

  class EditError < StandardError; end
  description "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits."
  input_schema({
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the file to edit (relative or absolute)" },
      edits: {
        type: "array",
        description: "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits.",
        items: {
          type: "object",
          properties: {
            oldText: { type: "string", description: "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call." },
            newText: { type: "string", description: "Replacement text for this targeted edit." }
          },
          required: [ "oldText", "newText" ]
        }
      }
    },
    required: [ "path", "edits" ]
  })

  def execute(input)
    path = input[:path]
    edits = prepare_edits(input[:edits])

    return "Edit tool input is invalid. edits must contain at least one replacement." if !edits.is_a?(Array) || edits.empty?

    absolute_path = ToolUtils.resolve_to_cwd(path)

    ToolUtils.with_file_mutation_lock(absolute_path) do
      begin
        File.open(absolute_path, File::RDWR) { }
      rescue SystemCallError => e
        return "Could not edit file: #{path}. Error code: #{e.class.name.split("::").last}."
      end

      raw_content = File.binread(absolute_path)

      bom = raw_content.start_with?("\xEF\xBB\xBF".b) ? "\xEF\xBB\xBF".b : "".b
      content_without_bom = bom.empty? ? raw_content : raw_content.byteslice(3..)
      content_utf8 = content_without_bom.force_encoding("UTF-8")

      original_ending = detect_line_ending(content_utf8)
      normalized_content = normalize_to_lf(content_utf8)
      base_content, new_content = apply_edits_to_normalized_content(normalized_content, edits, path)

      restored = restore_line_endings(new_content, original_ending)
      final_bytes = bom + restored.encode("UTF-8").b

      File.binwrite(absolute_path, final_bytes)
      "Successfully replaced #{edits.length} block(s) in #{path}."
    end
  rescue EditError => e
    e.message
  rescue StandardError => e
    "Error editing file: #{e.message}"
  end

  private

  def prepare_edits(edits)
    return JSON.parse(edits, symbolize_names: true) if edits.is_a?(String)

    edits
  end

  def detect_line_ending(content)
    crlf_index = content.index("\r\n")
    lf_index = content.index("\n")
    return "\n" unless lf_index
    return "\n" unless crlf_index

    crlf_index < lf_index ? "\r\n" : "\n"
  end

  def normalize_to_lf(text)
    text.gsub("\r\n", "\n").gsub("\r", "\n")
  end

  def restore_line_endings(text, ending)
    ending == "\r\n" ? text.gsub("\n", "\r\n") : text
  end

  def normalize_for_fuzzy_match(text)
    text
      .unicode_normalize(:nfkc)
      .split("\n", -1)
      .map(&:rstrip)
      .join("\n")
      .gsub(/[\u2018\u2019\u201A\u201B]/, "'")
      .gsub(/[\u201C\u201D\u201E\u201F]/, '"')
      .gsub(/[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]/, "-")
      .gsub(/[\u00A0\u2002-\u200A\u202F\u205F\u3000]/, " ")
  end

  def fuzzy_find_text(content, old_text)
    exact_index = content.index(old_text)
    if exact_index
      return {
        found: true,
        index: exact_index,
        match_length: old_text.length,
        used_fuzzy_match: false,
        content_for_replacement: content
      }
    end

    fuzzy_content = normalize_for_fuzzy_match(content)
    fuzzy_old_text = normalize_for_fuzzy_match(old_text)
    fuzzy_index = fuzzy_content.index(fuzzy_old_text)

    return { found: false, index: -1, match_length: 0, used_fuzzy_match: false, content_for_replacement: content } unless fuzzy_index

    {
      found: true,
      index: fuzzy_index,
      match_length: fuzzy_old_text.length,
      used_fuzzy_match: true,
      content_for_replacement: fuzzy_content
    }
  end

  def count_occurrences(content, old_text)
    fuzzy_content = normalize_for_fuzzy_match(content)
    fuzzy_old_text = normalize_for_fuzzy_match(old_text)
    fuzzy_content.split(fuzzy_old_text, -1).length - 1
  end

  def apply_edits_to_normalized_content(normalized_content, edits, path)
    normalized_edits = edits.map do |edit|
      {
        oldText: normalize_to_lf(edit[:oldText]),
        newText: normalize_to_lf(edit[:newText])
      }
    end

    normalized_edits.each_with_index do |edit, index|
      raise EditError, empty_old_text_error(path, index, normalized_edits.length) if edit[:oldText].empty?
    end

    initial_matches = normalized_edits.map { |edit| fuzzy_find_text(normalized_content, edit[:oldText]) }
    base_content = initial_matches.any? { |match| match[:used_fuzzy_match] } ? normalize_for_fuzzy_match(normalized_content) : normalized_content

    matched_edits = []
    normalized_edits.each_with_index do |edit, index|
      match = fuzzy_find_text(base_content, edit[:oldText])
      raise EditError, not_found_error(path, index, normalized_edits.length) unless match[:found]

      occurrences = count_occurrences(base_content, edit[:oldText])
      raise EditError, duplicate_error(path, index, normalized_edits.length, occurrences) if occurrences > 1

      matched_edits << {
        edit_index: index,
        match_index: match[:index],
        match_length: match[:match_length],
        new_text: edit[:newText]
      }
    end

    matched_edits.sort_by! { |edit| edit[:match_index] }
    matched_edits.each_cons(2) do |previous, current|
      next unless previous[:match_index] + previous[:match_length] > current[:match_index]

      raise EditError, "edits[#{previous[:edit_index]}] and edits[#{current[:edit_index]}] overlap in #{path}. Merge them into one edit or target disjoint regions."
    end

    new_content = base_content.dup
    matched_edits.reverse_each do |edit|
      new_content = new_content[0...edit[:match_index]] + edit[:new_text] + new_content[(edit[:match_index] + edit[:match_length])..]
    end

    raise EditError, no_change_error(path, normalized_edits.length) if base_content == new_content

    [ base_content, new_content ]
  end

  def not_found_error(path, edit_index, total_edits)
    return "Could not find the exact text in #{path}. The old text must match exactly including all whitespace and newlines." if total_edits == 1

    "Could not find edits[#{edit_index}] in #{path}. The oldText must match exactly including all whitespace and newlines."
  end

  def duplicate_error(path, edit_index, total_edits, occurrences)
    if total_edits == 1
      return "Found #{occurrences} occurrences of the text in #{path}. The text must be unique. Please provide more context to make it unique."
    end

    "Found #{occurrences} occurrences of edits[#{edit_index}] in #{path}. Each oldText must be unique. Please provide more context to make it unique."
  end

  def empty_old_text_error(path, edit_index, total_edits)
    return "oldText must not be empty in #{path}." if total_edits == 1

    "edits[#{edit_index}].oldText must not be empty in #{path}."
  end

  def no_change_error(path, total_edits)
    if total_edits == 1
      return "No changes made to #{path}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
    end

    "No changes made to #{path}. The replacements produced identical content."
  end
end
