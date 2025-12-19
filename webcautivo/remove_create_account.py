import os

file_path = r'c:\Users\admin\Downloads\proyecto\Facebook - Inicia sesión o regístrate (13_12_2025 22：36：49).html'

if not os.path.exists(file_path):
    print(f"File not found: {file_path}")
    exit(1)

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Target text
target_text = "Crear cuenta nueva"
index = content.find(target_text)

if index == -1:
    print(f"Could not find text '{target_text}'")
    exit(1)

print(f"Found text at index {index}")

# We need to find the specific container. 
# User provided start:
# <div data-bloks-name="bk.components.Flexbox" class="wbloks_1" style="pointer-events:none;padding-top:0px;align-items:center;flex-direction:row;justify-content:center">

# Key unique style part:
style_part = "padding-top:0px;align-items:center;flex-direction:row;justify-content:center"

# We search backwards for this style string
style_index = content.rfind(style_part, 0, index)

if style_index == -1:
    print("Could not find the style signature of the container.")
    exit(1)

# Now find the start of the div tag containing this style
# It should be `<div ... style=...`
# We search backwards for `<div` from style_index
div_start_index = content.rfind("<div", 0, style_index)

if div_start_index == -1:
    print("Could not find start of div tag.")
    exit(1)

print(f"Found start of block at {div_start_index}")

# Verify it corresponds to the right block by checking some other attribute if possible, e.g. data-bloks-name
# The user said data-bloks-name="bk.components.Flexbox".
# Let's check if that substring exists between div_start_index and style_index
chunk_header = content[div_start_index:style_index]
if "bk.components.Flexbox" not in chunk_header:
    print("Warning: Determine block header might be incorrect. 'bk.components.Flexbox' not found in header.")
    print(f"Header found: {chunk_header}")
    # We might proceed or stop. Let's proceed but verify context.

# Now find the end.
# The user snippet ends with many closing divs. 
# And the text "Crear cuenta nueva" is inside a span inside a span inside ...
# Let's verify the text "Crear cuenta nueva" context.
# User: <span ...>Crear cuenta nueva</span></span></div></div>...

# We can find the end of the span wrapping "Crear cuenta nueva"
# And then count the closing divs? 
# The user snippet provided has a very specific structure.
# Let's looking for the end of the user provided snippet which is `</div></div></div></div></div></div></div></div></div></div>`
# That's 10 </div>s.
# But checking exact number of divs is risky if formatting changed.
# However, the user provided snippet seems to be the entire "flexbox" component.
# Let's count matching divs from div_start_index.

def find_closing_match(full_text, start_pos):
    # Find the first > to end the opening tag
    tag_end = full_text.find('>', start_pos)
    if tag_end == -1: return -1
    
    # Simple stack counter
    count = 1
    pos = tag_end + 1
    max_len = len(full_text)
    
    while count > 0 and pos < max_len:
        next_open = full_text.find('<div', pos)
        next_close = full_text.find('</div>', pos)
        
        if next_close == -1:
            return -1 # broken html
            
        if next_open != -1 and next_open < next_close:
            count += 1
            pos = next_open + 4 # skip <div
        else:
            count -= 1
            pos = next_close + 6 # skip </div>
            
    return pos

end_index = find_closing_match(content, div_start_index)

if end_index == -1 or end_index < index:
    print("Could not calculate end of block using tag counting.")
    # Fallback: Searching for the long string of closing divs after the text
    # User had 10 closing divs
    closing_chain = "</div>" * 10
    chain_index = content.find(closing_chain, index)
    if chain_index != -1:
        end_index = chain_index + len(closing_chain)
        print(f"Found end using fallback closing chain at {end_index}")
    else:
        print("Fallback failed.")
        exit(1)

print(f"Block defined from {div_start_index} to {end_index}")
print("Removing block...")

new_content = content[:div_start_index] + content[end_index:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("File updated successfully.")
