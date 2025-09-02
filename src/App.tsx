import React, { useState, useRef, useCallback } from 'react';
import { Edit3, Pin, Move } from 'lucide-react';

function App() {
  const [isLogoHovered, setIsLogoHovered] = useState(false);
  const [isEditMode, setIsEditMode] = useState(false);
  const [isPinned, setIsPinned] = useState(false);
  const [logoPosition, setLogoPosition] = useState({ x: 0, y: 0 });
  const [logoSize, setLogoSize] = useState({ width: 200, height: 60 });
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [resizeHandle, setResizeHandle] = useState('');
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [resizeStart, setResizeStart] = useState({ x: 0, y: 0, width: 0, height: 0, logoX: 0, logoY: 0 });
  const [hasBeenMoved, setHasBeenMoved] = useState(false);
  const [isAbsolutePositioned, setIsAbsolutePositioned] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [currentTheme, setCurrentTheme] = useState('default');
  const [isThemeDropdownOpen, setIsThemeDropdownOpen] = useState(false);
  const [themes, setThemes] = useState({
    default: 'Default',
    theme1: 'Theme1',
    theme2: 'Theme2',
    theme3: 'Theme3'
  });
  const [editingTheme, setEditingTheme] = useState<string | null>(null);
  const [editingThemeName, setEditingThemeName] = useState('');
  
  const logoRef = useRef<HTMLDivElement>(null);

  // Load saved position and theme from localStorage on component mount
  React.useEffect(() => {
    const savedPosition = localStorage.getItem('logoPosition');
    const savedSize = localStorage.getItem('logoSize');
    const savedMoved = localStorage.getItem('logoHasBeenMoved');
    const savedTheme = localStorage.getItem('currentTheme');
    const savedThemes = localStorage.getItem('themes');
    
    if (savedPosition) {
      const position = JSON.parse(savedPosition);
      setLogoPosition(position);
      setHasBeenMoved(true);
      setIsAbsolutePositioned(true);
    }
    
    if (savedSize) {
      const size = JSON.parse(savedSize);
      setLogoSize(size);
    }
    
    if (savedMoved === 'true') {
      setHasBeenMoved(true);
    }
    
    if (savedTheme) {
      setCurrentTheme(savedTheme);
    }
    
    if (savedThemes) {
      const parsedThemes = JSON.parse(savedThemes);
      setThemes(parsedThemes);
    }
    
    // Set loading to false after all data is loaded
    setIsLoading(false);
  }, []);

  // Save position to localStorage whenever it changes
  React.useEffect(() => {
    if (hasBeenMoved) {
      localStorage.setItem('logoPosition', JSON.stringify(logoPosition));
      localStorage.setItem('logoSize', JSON.stringify(logoSize));
      localStorage.setItem('logoHasBeenMoved', 'true');
    }
  }, [logoPosition, logoSize, hasBeenMoved]);

  // Save themes to localStorage whenever they change
  React.useEffect(() => {
    localStorage.setItem('themes', JSON.stringify(themes));
  }, [themes]);

  // Handle mouse down for dragging
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (!isEditMode || isPinned) return;
    
    e.preventDefault();
    setIsDragging(true);
    setDragStart({
      x: e.clientX - logoPosition.x,
      y: e.clientY - logoPosition.y
    });
  }, [isEditMode, isPinned, logoPosition]);

  // Handle mouse move for dragging
  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (isDragging && isEditMode && !isPinned) {
      const newX = e.clientX - dragStart.x;
      const newY = e.clientY - dragStart.y;
      
      // Keep within viewport bounds (accounting for header)
      const headerHeight = Math.max(60, Math.min(120, window.innerHeight * 0.1)); // Header is 10% of viewport height
      const maxX = window.innerWidth - logoSize.width;
      const maxY = window.innerHeight - logoSize.height - headerHeight;
      
      // Add some padding to keep logo visible
      const padding = 20;
      const constrainedPosition = {
        x: Math.max(padding, Math.min(newX, maxX - padding)),
        y: Math.max(padding, Math.min(newY, maxY - padding))
      };
      
      setLogoPosition(constrainedPosition);
      
      // Mark as moved if this is the first drag
      if (!hasBeenMoved) {
        setHasBeenMoved(true);
      }
    }
    
    if (isResizing && isEditMode && !isPinned) {
      const deltaX = e.clientX - resizeStart.x;
      const deltaY = e.clientY - resizeStart.y;
      
      let newWidth = resizeStart.width;
      let newHeight = resizeStart.height;
      let newX = resizeStart.logoX;
      let newY = resizeStart.logoY;
      
      // Simple resize logic - only change size, keep position locked
      switch (resizeHandle) {
        case 'nw': // Top-left corner
          newWidth = Math.max(100, resizeStart.width - deltaX);
          newHeight = Math.max(40, resizeStart.height - deltaY);
          newX = resizeStart.logoX + (resizeStart.width - newWidth);
          newY = resizeStart.logoY + (resizeStart.height - newHeight);
          break;
        case 'ne': // Top-right corner
          newWidth = Math.max(100, resizeStart.width + deltaX);
          newHeight = Math.max(40, resizeStart.height - deltaY);
          newY = resizeStart.logoY + (resizeStart.height - newHeight);
          break;
        case 'sw': // Bottom-left corner
          newWidth = Math.max(100, resizeStart.width - deltaX);
          newHeight = Math.max(40, resizeStart.height + deltaY);
          newX = resizeStart.logoX + (resizeStart.width - newWidth);
          break;
        case 'se': // Bottom-right corner
          newWidth = Math.max(100, resizeStart.width + deltaX);
          newHeight = Math.max(40, resizeStart.height + deltaY);
          break;
        case 'n': // Top edge
          newHeight = Math.max(40, resizeStart.height - deltaY);
          newY = resizeStart.logoY + (resizeStart.height - newHeight);
          break;
        case 's': // Bottom edge
          newHeight = Math.max(40, resizeStart.height + deltaY);
          break;
        case 'w': // Left edge
          newWidth = Math.max(100, resizeStart.width - deltaX);
          newX = resizeStart.logoX + (resizeStart.width - newWidth);
          break;
        case 'e': // Right edge
          newWidth = Math.max(100, resizeStart.width + deltaX);
          break;
      }
      
      setLogoSize({ width: newWidth, height: newHeight });
      setLogoPosition({ x: newX, y: newY });
    }
  }, [isDragging, isResizing, isEditMode, isPinned, dragStart, resizeStart, logoSize, resizeHandle, hasBeenMoved]);

  // Handle mouse up
  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setIsResizing(false);
    setResizeHandle('');
  }, []);

  // Add global event listeners
  React.useEffect(() => {
    if (isDragging || isResizing) {
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
      return () => {
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };
    }
  }, [isDragging, isResizing, handleMouseMove, handleMouseUp]);

  // Handle resize handle mouse down
  const handleResizeMouseDown = useCallback((e: React.MouseEvent, handle: string) => {
    if (!isEditMode || isPinned) return;
    
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    setResizeHandle(handle);
    
    // Get current position from DOM element instead of saved position
    const logoRect = logoRef.current?.getBoundingClientRect();
    const currentX = logoRect ? logoRect.left : logoPosition.x;
    const currentY = logoRect ? logoRect.top : logoPosition.y;
    
    setResizeStart({
      x: e.clientX,
      y: e.clientY,
      width: logoSize.width,
      height: logoSize.height,
      logoX: currentX,
      logoY: currentY
    });
  }, [isEditMode, isPinned, logoSize, logoPosition]);

  // Toggle edit mode
  const toggleEditMode = useCallback(() => {
    if (!isEditMode) {
      // Entering edit mode
      if (!hasBeenMoved) {
        // First time entering edit mode - capture current position from DOM
        const logoRect = logoRef.current?.getBoundingClientRect();
        if (logoRect) {
          const currentPos = {
            x: logoRect.left,
            y: logoRect.top
          };
          const currentSize = {
            width: logoRect.width,
            height: logoRect.height
          };
          setLogoPosition(currentPos);
          setLogoSize(currentSize);
          // Don't set hasBeenMoved to true here - only when user actually moves/resizes
        }
      }
      setIsAbsolutePositioned(true);
    } else {
      // Exiting edit mode
      setIsDragging(false);
      setIsResizing(false);
      // Keep absolute positioning if it has been moved
      if (!hasBeenMoved) {
        setIsAbsolutePositioned(false);
      }
    }
    setIsEditMode(!isEditMode);
  }, [isEditMode, hasBeenMoved]);

  // Toggle pin
  const togglePin = useCallback(() => {
    setIsPinned(!isPinned);
  }, [isPinned]);

  // Change theme and reset all elements to default positions
  const changeTheme = useCallback((theme: string) => {
    if (theme === 'default') {
      // Reset logo to original position
      setHasBeenMoved(false);
      setIsAbsolutePositioned(false);
      setLogoPosition({ x: 0, y: 0 });
      setLogoSize({ width: 200, height: 60 });
      setIsEditMode(false);
      setIsPinned(false);
      localStorage.removeItem('logoPosition');
      localStorage.removeItem('logoSize');
      localStorage.removeItem('logoHasBeenMoved');
    }
    
    setCurrentTheme(theme);
    setIsThemeDropdownOpen(false);
    
    // Save theme preference
    localStorage.setItem('currentTheme', theme);
  }, []);

  // Start editing a theme name
  const startEditingTheme = useCallback((themeKey: string) => {
    if (themeKey === 'default') return; // Don't allow editing default theme
    setEditingTheme(themeKey);
    setEditingThemeName(themes[themeKey as keyof typeof themes]);
  }, [themes]);

  // Save theme name edit
  const saveThemeName = useCallback(() => {
    if (editingTheme && editingThemeName.trim()) {
      setThemes(prev => ({
        ...prev,
        [editingTheme]: editingThemeName.trim()
      }));
    }
    setEditingTheme(null);
    setEditingThemeName('');
  }, [editingTheme, editingThemeName]);

  // Cancel theme name edit
  const cancelThemeEdit = useCallback(() => {
    setEditingTheme(null);
    setEditingThemeName('');
  }, []);

  // Add keyboard shortcut to reset to default theme (Ctrl+R or Cmd+R)
  React.useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Only trigger if not currently resizing or dragging
      if ((e.ctrlKey || e.metaKey) && e.key === 'r' && !isResizing && !isDragging) {
        e.preventDefault();
        changeTheme('default');
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [changeTheme, isResizing, isDragging]);

  // Close dropdown when clicking outside
  React.useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (isThemeDropdownOpen) {
        const target = e.target as HTMLElement;
        if (!target.closest('[data-theme-dropdown]')) {
          setIsThemeDropdownOpen(false);
        }
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isThemeDropdownOpen]);

  return (
    <div style={{ 
      minHeight: '100vh', 
      backgroundColor: '#ffffff',
      width: '100%',
      height: '100%'
    }}>
      {/* Clean Header */}
      <header style={{
        backgroundColor: '#0f172a', // Much darker blue
        height: '10vh', // 10% of viewport height
        minHeight: '60px', // Minimum height for very small screens
        maxHeight: '120px', // Maximum height for very large screens
        boxShadow: '0 2px 10px rgba(0, 0, 0, 0.1)',
        position: 'sticky',
        top: 0,
        zIndex: 1000,
        width: '100%',
        display: 'flex',
        alignItems: 'center',
        paddingLeft: '20%' // Align with main content margins
      }}>
        {/* Standalone Logo Container */}
        {!isLoading && (
          <div 
            ref={logoRef}
            style={{
              position: isAbsolutePositioned ? 'absolute' : 'relative',
              left: isAbsolutePositioned ? `${logoPosition.x}px` : 'auto',
              top: isAbsolutePositioned ? `${logoPosition.y}px` : 'auto',
              width: isAbsolutePositioned && hasBeenMoved ? `${logoSize.width}px` : 'auto',
              height: isAbsolutePositioned && hasBeenMoved ? `${logoSize.height}px` : 'auto',
              padding: '0.5rem 1rem',
              borderRadius: '8px',
              border: isEditMode 
                ? '2px dashed rgba(255, 255, 255, 0.8)' 
                : isLogoHovered 
                  ? '2px solid rgba(255, 255, 255, 0.3)' 
                  : '2px solid transparent',
              transition: isEditMode ? 'none' : 'all 0.2s ease',
              cursor: isEditMode && !isPinned ? 'move' : 'pointer',
              zIndex: isAbsolutePositioned ? 1001 : 'auto',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
            onMouseEnter={() => setIsLogoHovered(true)}
            onMouseLeave={() => setIsLogoHovered(false)}
            onMouseDown={handleMouseDown}
          >
          {/* Logo Text */}
          <div style={{
            color: '#ffffff',
            fontSize: '1.5rem',
            fontWeight: '700',
            letterSpacing: '-0.025em',
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", sans-serif',
            pointerEvents: 'none'
          }}>
            life.game
          </div>
          
          {/* Resize Handles - Only show in edit mode */}
          {isEditMode && !isPinned && (
            <>
              {/* Corner handles */}
              <div
                style={{
                  position: 'absolute',
                  top: '-4px',
                  left: '-4px',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'nw-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'nw')}
              />
              <div
                style={{
                  position: 'absolute',
                  top: '-4px',
                  right: '-4px',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'ne-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'ne')}
              />
              <div
                style={{
                  position: 'absolute',
                  bottom: '-4px',
                  left: '-4px',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'sw-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'sw')}
              />
              <div
                style={{
                  position: 'absolute',
                  bottom: '-4px',
                  right: '-4px',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'se-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'se')}
              />
              
              {/* Edge handles */}
              <div
                style={{
                  position: 'absolute',
                  top: '-4px',
                  left: '50%',
                  transform: 'translateX(-50%)',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'n-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'n')}
              />
              <div
                style={{
                  position: 'absolute',
                  bottom: '-4px',
                  left: '50%',
                  transform: 'translateX(-50%)',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 's-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 's')}
              />
              <div
                style={{
                  position: 'absolute',
                  top: '50%',
                  left: '-4px',
                  transform: 'translateY(-50%)',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'w-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'w')}
              />
              <div
                style={{
                  position: 'absolute',
                  top: '50%',
                  right: '-4px',
                  transform: 'translateY(-50%)',
                  width: '8px',
                  height: '8px',
                  backgroundColor: 'rgba(255, 255, 255, 0.8)',
                  border: '1px solid #0f172a',
                  cursor: 'e-resize'
                }}
                onMouseDown={(e) => handleResizeMouseDown(e, 'e')}
              />
            </>
          )}
          
          {/* Hover Frame with Buttons */}
          {(isLogoHovered || isEditMode) && (
            <div style={{
              position: 'absolute',
              top: '-8px',
              right: '-8px',
              display: 'flex',
              gap: '4px',
              zIndex: 10
            }}>
              {/* Edit Button */}
              <button
                onClick={toggleEditMode}
                style={{
                  width: '24px',
                  height: '24px',
                  borderRadius: '4px',
                  backgroundColor: isEditMode ? '#ffffff' : 'rgba(255, 255, 255, 0.9)',
                  border: 'none',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  transition: 'all 0.2s ease',
                  boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.backgroundColor = '#ffffff';
                  e.currentTarget.style.transform = 'scale(1.1)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = isEditMode ? '#ffffff' : 'rgba(255, 255, 255, 0.9)';
                  e.currentTarget.style.transform = 'scale(1)';
                }}
                title={isEditMode ? "Exit edit mode" : "Edit logo"}
              >
                {isEditMode ? <Move size={12} color="#0f172a" /> : <Edit3 size={12} color="#0f172a" />}
              </button>
              
              {/* Pin Button */}
              <button
                onClick={togglePin}
                style={{
                  width: '24px',
                  height: '24px',
                  borderRadius: '4px',
                  backgroundColor: isPinned ? '#ffffff' : 'rgba(255, 255, 255, 0.9)',
                  border: 'none',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  transition: 'all 0.2s ease',
                  boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.backgroundColor = '#ffffff';
                  e.currentTarget.style.transform = 'scale(1.1)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = isPinned ? '#ffffff' : 'rgba(255, 255, 255, 0.9)';
                  e.currentTarget.style.transform = 'scale(1)';
                }}
                title={isPinned ? "Unpin logo" : "Pin logo"}
              >
                <Pin size={12} color={isPinned ? "#dc2626" : "#0f172a"} />
              </button>
            </div>
          )}
      </div>
        )}
      </header>

            {/* Theme Dropdown - Always visible in top-right corner */}
      <div 
        data-theme-dropdown
        style={{
          position: 'fixed',
          top: '20px',
          right: '20px',
          zIndex: 1002
        }}
      >
        <button
          onClick={() => setIsThemeDropdownOpen(!isThemeDropdownOpen)}
          style={{
            padding: '8px 12px',
            backgroundColor: '#1e3a8a',
            color: 'white',
            border: 'none',
            borderRadius: '6px',
            fontSize: '12px',
            cursor: 'pointer',
            boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
            transition: 'all 0.2s ease',
            display: 'flex',
            alignItems: 'center',
            gap: '4px'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.backgroundColor = '#1e40af';
            e.currentTarget.style.transform = 'scale(1.05)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.backgroundColor = '#1e3a8a';
            e.currentTarget.style.transform = 'scale(1)';
          }}
        >
          Themes
          <span style={{ fontSize: '10px' }}>▼</span>
        </button>
        
        {/* Dropdown Menu */}
        {isThemeDropdownOpen && (
          <div style={{
            position: 'absolute',
            top: '100%',
            right: '0',
            marginTop: '4px',
            backgroundColor: 'white',
            border: '1px solid #e5e7eb',
            borderRadius: '6px',
            boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
            minWidth: '120px',
            overflow: 'hidden'
          }}>
            {/* Default Theme - Always at top, not editable */}
            <button
              onClick={() => changeTheme('default')}
              style={{
                width: '100%',
                padding: '8px 12px',
                backgroundColor: currentTheme === 'default' ? '#f3f4f6' : 'transparent',
                color: currentTheme === 'default' ? '#1e3a8a' : '#374151',
                border: 'none',
                fontSize: '12px',
                cursor: 'pointer',
                textAlign: 'left',
                transition: 'all 0.2s ease',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between'
              }}
              onMouseEnter={(e) => {
                if (currentTheme !== 'default') {
                  e.currentTarget.style.backgroundColor = '#f9fafb';
                }
              }}
              onMouseLeave={(e) => {
                if (currentTheme !== 'default') {
                  e.currentTarget.style.backgroundColor = 'transparent';
                }
              }}
            >
              <span>{themes.default}</span>
              <span style={{ fontSize: '10px', color: '#9ca3af' }}>•</span>
            </button>
            
            {/* Divider */}
            <div style={{
              height: '1px',
              backgroundColor: '#e5e7eb',
              margin: '4px 0'
            }} />
            
            {/* Editable Themes */}
            {Object.entries(themes).filter(([key]) => key !== 'default').map(([themeKey, themeName]) => (
              <div key={themeKey} style={{
                display: 'flex',
                alignItems: 'center',
                padding: '8px 12px',
                backgroundColor: currentTheme === themeKey ? '#f3f4f6' : 'transparent',
                transition: 'all 0.2s ease',
                cursor: 'pointer'
              }}
              onMouseEnter={(e) => {
                if (currentTheme !== themeKey) {
                  e.currentTarget.style.backgroundColor = '#f9fafb';
                }
              }}
              onMouseLeave={(e) => {
                if (currentTheme !== themeKey) {
                  e.currentTarget.style.backgroundColor = 'transparent';
                }
              }}
              onClick={() => changeTheme(themeKey)}
              >
                {editingTheme === themeKey ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px', width: '100%' }}>
                    <input
                      type="text"
                      value={editingThemeName}
                      onChange={(e) => setEditingThemeName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          saveThemeName();
                        } else if (e.key === 'Escape') {
                          cancelThemeEdit();
                        }
                      }}
                      onBlur={saveThemeName}
                      style={{
                        border: '1px solid #d1d5db',
                        borderRadius: '4px',
                        padding: '2px 6px',
                        fontSize: '12px',
                        flex: 1,
                        outline: 'none'
                      }}
                      autoFocus
                    />
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        saveThemeName();
                      }}
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        fontSize: '10px',
                        color: '#10b981'
                      }}
                    >
                      ✓
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        cancelThemeEdit();
                      }}
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        fontSize: '10px',
                        color: '#ef4444'
                      }}
                    >
                      ✕
                    </button>
                  </div>
                ) : (
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
                    <span style={{
                      color: currentTheme === themeKey ? '#1e3a8a' : '#374151',
                      fontSize: '12px'
                    }}>
                      {themeName}
                    </span>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        startEditingTheme(themeKey);
                      }}
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        fontSize: '10px',
                        color: '#6b7280',
                        padding: '2px',
                        borderRadius: '2px'
                      }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor = '#f3f4f6';
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = 'transparent';
                      }}
                    >
                      ✏️
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Main Content Area with 20% margins */}
      <main style={{
        marginLeft: '20%',
        marginRight: '20%',
        minHeight: '90vh', // Remaining viewport height after header
        backgroundColor: '#ffffff',
        padding: '2rem 0'
      }}>
        {/* Content will go here */}
      </main>
      </div>
  );
}

export default App;