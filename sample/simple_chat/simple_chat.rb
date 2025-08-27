require 'curses'
require_relative 'chat_client'

class SimpleChat
  def initialize(model, api_key)
    @client = ChatClient.new(model, api_key)
    @messages = []
    @current_input = ""
    @selected_model = model
    @available_models = [
      'claude-opus-4-20250514',
      'claude-sonnet-4-20250514',
      'claude-opus-4-1-20250805',
      'claude-3-5-haiku-20241022',
      'gpt-4',
      'gpt-3.5-turbo',
      'llama-3.1-8b-instant',
      'llama-3.3-70b-versatile',
      'meta-llama/llama-guard-4-12b',
      'openai/gpt-oss-120b',
      'openai/gpt-oss-20b'
    ]
    @dropdown_visible = false
    @dropdown_index = 0
    @scroll_offset = 0
  end

  def start
    Curses.init_screen
    Curses.start_color
    Curses.use_default_colors
    Curses.cbreak
    Curses.noecho
    Curses.stdscr.keypad(true)

    setup_colors

    begin
      main_loop
    ensure
      Curses.close_screen
    end
  end

  private

  def setup_colors
    Curses.init_pair(1, Curses::COLOR_GREEN, -1)
    Curses.init_pair(2, Curses::COLOR_BLUE, -1)
    Curses.init_pair(3, Curses::COLOR_YELLOW, -1)
    Curses.init_pair(4, Curses::COLOR_RED, -1)
    Curses.init_pair(5, Curses::COLOR_CYAN, -1)
  end

  def main_loop
    loop do
      draw_interface

      ch = Curses.stdscr.getch

      # Convert ch to integer if it's a string
      ch_code = ch.is_a?(String) ? ch.ord : ch

      case ch_code
      when 'q'.ord
        break
      when 9 # Tab key
        @dropdown_visible = !@dropdown_visible
      when Curses::KEY_UP
        handle_up_key
      when Curses::KEY_DOWN
        handle_down_key
      when 10, 13 # Enter key
        handle_enter_key
      when Curses::KEY_BACKSPACE, 127, 8
        handle_backspace
      else
        if ch_code >= 32 && ch_code <= 126 && !@dropdown_visible
          @current_input += ch_code.chr
        end
      end
    end
  end

  def handle_up_key
    if @dropdown_visible
      @dropdown_index = (@dropdown_index - 1) % @available_models.length
    end
  end

  def handle_down_key
    if @dropdown_visible
      @dropdown_index = (@dropdown_index + 1) % @available_models.length
    end
  end

  def handle_enter_key
    if @dropdown_visible
      @selected_model = @available_models[@dropdown_index]
      @client.model = @selected_model
      @dropdown_visible = false
    elsif !@current_input.strip.empty?
      send_message(@current_input.strip)
      @current_input = ""
    end
  end

  def handle_backspace
    if !@dropdown_visible && @current_input.length > 0
      @current_input = @current_input[0...-1]
    end
  end

  def send_message(message)
    @messages << { role: 'user', content: message }

    begin
      response = @client.send_message(message)
      @messages << { role: 'assistant', content: response }
    rescue => e
      @messages << { role: 'error', content: "Error: #{e.message}" }
    end
  end

  def draw_interface
    Curses.clear

    height = Curses.lines
    width = Curses.cols

    # Split screen with proper spacing - leave 1 space between panels
    chat_width = (width * 0.7).to_i - 1
    panel_x = chat_width + 1
    panel_width = width - panel_x

    # Ensure minimum widths
    if panel_width < 15
      chat_width = width - 16  # 15 for panel + 1 for gap
      panel_x = chat_width + 1
      panel_width = 15
    end

    draw_chat_panel(0, 0, height, chat_width)

    # Draw the gap between panels
    (0...height).each do |i|
      Curses.setpos(i, chat_width)
      Curses.addstr(" ")
    end

    draw_control_panel(0, panel_x, height, panel_width)

    Curses.refresh
  end

  def draw_chat_panel(y, x, height, width)
    # Draw border
    draw_box(y, x, height, width, " Chat ")

    # Draw messages
    draw_messages(y + 1, x + 1, height - 4, width - 2)

    # Draw input area
    draw_input_area(y + height - 3, x + 1, width - 2)
  end

  def draw_control_panel(y, x, height, width)
    # Draw border
    draw_box(y, x, height, width, " Settings ")

    # Draw model selection
    draw_model_selection(y + 2, x + 1, width - 2)

    # Draw instructions
    draw_instructions(y + height - 8, x + 1, width - 2)
  end

  def draw_box(y, x, height, width, title)
    return if width < 3 || height < 3  # Too small to draw a box

    Curses.attron(Curses.color_pair(5)) # Cyan

    # Top border - draw character by character
    Curses.setpos(y, x)
    Curses.addstr("┌")

    # Add title and fill rest with dashes
    title_len = [ title.length, width - 2 ].min  # Don't exceed available space
    Curses.addstr(title[0, title_len]) if title_len > 0


    # Fill remaining space with dashes up to the right corner
    remaining = width - 1 - title_len - 1  # total - left corner - title - right corner
    if remaining > 0
      Curses.addstr("─" * remaining)
    end

    # Right corner of top border
    if width > 1
      Curses.addstr("┐")
    end

    # Side borders
    (1...height-1).each do |i|
      # Left border
      Curses.setpos(y + i, x)
      Curses.addstr("│")

      # Right border
      if width > 1
        Curses.setpos(y + i, x + width - 1)
        Curses.addstr("│")
      end
    end

    # Bottom border
    if height > 1
      Curses.setpos(y + height - 1, x)
      Curses.addstr("└")

      # Fill with dashes
      if width > 2
        Curses.addstr("─" * (width - 2))
      end

      # Right corner
      if width > 1
        Curses.addstr("┘")
      end
    end

    Curses.attroff(Curses.color_pair(5))
  end

  def draw_messages(y, x, height, width)
    return if @messages.empty?

    visible_messages = @messages.last([ height, @messages.length ].min)

    visible_messages.each_with_index do |message, i|
      Curses.setpos(y + i, x)

      case message[:role]
      when 'user'
        Curses.attron(Curses.color_pair(1)) # Green
        prefix = "You: "
      when 'assistant'
        Curses.attron(Curses.color_pair(2)) # Blue
        prefix = "AI: "
      when 'error'
        Curses.attron(Curses.color_pair(4)) # Red
        prefix = "Error: "
      end

      content = (prefix + message[:content]).slice(0, width)
      Curses.addstr(content)
      Curses.attroff(Curses.color_pair(1) | Curses.color_pair(2) | Curses.color_pair(4))
    end
  end

  def draw_input_area(y, x, width)
    Curses.setpos(y, x)
    Curses.attron(Curses.color_pair(3)) # Yellow
    input_text = "> #{@current_input}#{@current_input.length < width - 3 ? '_' : ''}"
    Curses.addstr(input_text.slice(0, width))
    Curses.attroff(Curses.color_pair(3))
  end

  def draw_model_selection(y, x, width)
    Curses.setpos(y, x)
    model_text = "Model: #{@selected_model}"
    Curses.addstr(model_text.slice(0, width))

    if @dropdown_visible
      dropdown_height = [ @available_models.length, 10 ].min
      @available_models.first(dropdown_height).each_with_index do |model, i|
        Curses.setpos(y + 2 + i, x)
        if i == @dropdown_index
          Curses.attron(Curses.color_pair(3)) # Highlight
        end
        option_text = "  #{model}"
        Curses.addstr(option_text.slice(0, width))
        Curses.attroff(Curses.color_pair(3))
      end
    else
      Curses.setpos(y + 1, x)
      Curses.addstr("(Tab to change)".slice(0, width))
    end
  end

  def draw_instructions(y, x, width)
    instructions = [
      "Controls:",
      "Tab - Toggle model menu",
      "↑/↓ - Navigate menu",
      "Enter - Select/Send",
      "q - Quit"
    ]

    instructions.each_with_index do |instruction, i|
      next if y + i >= Curses.lines - 1 # Don't draw outside screen
      Curses.setpos(y + i, x)
      Curses.addstr(instruction.slice(0, width))
    end
  end
end
