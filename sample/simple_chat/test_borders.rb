#!/usr/bin/env ruby

# Simple test script to check border rendering
require 'curses'

def test_borders
  Curses.init_screen
  Curses.start_color
  Curses.use_default_colors
  Curses.cbreak
  Curses.noecho

  begin
    height = Curses.lines
    width = Curses.cols
    
    # Same logic as the TUI
    chat_width = (width * 0.7).to_i - 1
    panel_x = chat_width + 1
    panel_width = width - panel_x
    
    Curses.init_pair(5, Curses::COLOR_CYAN, -1)
    
    # Draw chat panel border
    draw_test_box(0, 0, height, chat_width, " Chat ")
    
    # Draw settings panel border  
    draw_test_box(0, panel_x, height, panel_width, " Settings ")
    
    Curses.refresh
    
    # Show dimensions for debugging
    Curses.setpos(height - 2, 0)
    Curses.addstr("Terminal: #{width}x#{height}, Chat: #{chat_width}, Settings: #{panel_width} @ #{panel_x}")
    
    Curses.refresh
    sleep(3)
    
  ensure
    Curses.close_screen
  end
end

def draw_test_box(y, x, height, width, title)
  return if width < 3 || height < 3  # Too small to draw a box
  
  Curses.attron(Curses.color_pair(5)) # Cyan
  
  # Top border - draw character by character
  Curses.setpos(y, x)
  Curses.addstr("┌")
  
  # Add title and fill rest with dashes
  title_len = [title.length, width - 2].min  # Don't exceed available space
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
  
  # Side borders (just first few for testing)
  [1, 2, 3].each do |i|
    break if i >= height - 1
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

if __FILE__ == $0
  test_borders
end