import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Edit3, Pin, Move, Type } from 'lucide-react';

interface EditableElementProps {
  children: React.ReactNode;
  elementType?: 'button' | 'div' | 'img' | 'text';
  onTextChange?: (newText: string) => void;
  initialText?: string;
  className?: string;
  style?: React.CSSProperties;
  externalPosition?: { x: number; y: number };
  externalSize?: { width: number; height: number };
  externalHasBeenMoved?: boolean;
  externalIsAbsolutePositioned?: boolean;
  onPositionChange?: (position: { x: number; y: number }) => void;
  onSizeChange?: (size: { width: number; height: number }) => void;
}

const EditableElement: React.FC<EditableElementProps> = ({
  children,
  elementType = 'div',
  onTextChange,
  initialText,
  className = '',
  style = {},
  externalPosition,
  externalSize,
  externalHasBeenMoved,
  externalIsAbsolutePositioned,
  onPositionChange,
  onSizeChange
}) => {
  // Internal state - this is the source of truth
  const [isHovered, setIsHovered] = useState(false);
  const [isEditMode, setIsEditMode] = useState(false);
  const [isPinned, setIsPinned] = useState(false);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [resizeHandle, setResizeHandle] = useState('');
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [resizeStart, setResizeStart] = useState({ x: 0, y: 0, width: 0, height: 0, elementX: 0, elementY: 0 });
  const [hasBeenMoved, setHasBeenMoved] = useState(false);
  const [isAbsolutePositioned, setIsAbsolutePositioned] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isEditingText, setIsEditingText] = useState(false);
  const [currentText, setCurrentText] = useState<string | null>(initialText || null);
  const [isInitialized, setIsInitialized] = useState(false);

  const elementRef = useRef<HTMLDivElement>(null);

  // Helper function to enforce content area bounds (responsive margins)
  const enforceContentAreaBounds = useCallback((x: number, y: number, width: number, height: number) => {
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    
    // Responsive margins: minimum 16px, maximum 20% of viewport
    const leftMargin = Math.max(16, Math.min(viewportWidth * 0.2, viewportWidth * 0.1));
    const rightMargin = Math.max(16, Math.min(viewportWidth * 0.2, viewportWidth * 0.1));
    const contentAreaWidth = viewportWidth - leftMargin - rightMargin;
    
    // Responsive header height: 10% of viewport with min/max constraints
    const headerHeight = Math.max(60, Math.min(120, viewportHeight * 0.1));
    
    const maxX = leftMargin + contentAreaWidth - width;
    const maxY = viewportHeight - height - headerHeight;
    
    return {
      x: Math.max(leftMargin, Math.min(x, maxX)),
      y: Math.max(0, Math.min(y, maxY))
    };
  }, []);

  // Initialize element on mount - SIMPLIFIED
  useEffect(() => {
    // Initialize text from children if not provided
    if (currentText === null && elementType === 'button' && React.isValidElement(children)) {
      const buttonText = (children as React.ReactElement).props.children;
      if (typeof buttonText === 'string') {
        setCurrentText(buttonText);
      }
    }
    
    setIsInitialized(true);
  }, [children, elementType, currentText]);

  // Capture position and size after element is rendered
  useEffect(() => {
    if (isInitialized && elementRef.current && !hasBeenMoved) {
      const elementRect = elementRef.current.getBoundingClientRect();
      setPosition({ x: elementRect.left, y: elementRect.top });
      setSize({ width: elementRect.width, height: elementRect.height });
    }
  }, [isInitialized, hasBeenMoved]);

  // Apply external state only once on mount if provided
  useEffect(() => {
    if (isInitialized && externalPosition && externalSize) {
      setPosition(externalPosition);
      setSize(externalSize);
      setHasBeenMoved(externalHasBeenMoved || false);
      setIsAbsolutePositioned(externalIsAbsolutePositioned || false);
    }
  }, [isInitialized, externalPosition, externalSize, externalHasBeenMoved, externalIsAbsolutePositioned]);

  // Handle mouse down for dragging
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (!isEditMode || isPinned) return;
    
    e.preventDefault();
    setIsDragging(true);
    setDragStart({
      x: e.clientX - position.x,
      y: e.clientY - position.y
    });
  }, [isEditMode, isPinned, position]);

  // Handle mouse move for dragging and resizing
  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (isDragging && isEditMode && !isPinned) {
      const newX = e.clientX - dragStart.x;
      const newY = e.clientY - dragStart.y;
      
      // Enforce boundaries with padding
      const padding = 10;
      const constrainedPosition = enforceContentAreaBounds(
        newX - padding, 
        newY - padding, 
        size.width + (padding * 2), 
        size.height + (padding * 2)
      );
      
      const finalPosition = {
        x: constrainedPosition.x + padding,
        y: constrainedPosition.y + padding
      };
      
      setPosition(finalPosition);
      setHasBeenMoved(true);
      setIsAbsolutePositioned(true);

      // Notify parent of position change
      if (onPositionChange) {
        onPositionChange(finalPosition);
      }
    }
    
    if (isResizing && isEditMode && !isPinned) {
      const deltaX = e.clientX - resizeStart.x;
      const deltaY = e.clientY - resizeStart.y;
      
      let newWidth = resizeStart.width;
      let newHeight = resizeStart.height;
      let newX = resizeStart.elementX;
      let newY = resizeStart.elementY;
      
      // Resize logic - change size and adjust position to keep opposite corner fixed
      switch (resizeHandle) {
        case 'nw': // Top-left corner - keep bottom-right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 'ne': // Top-right corner - keep bottom-left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 'sw': // Bottom-left corner - keep top-right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newHeight = Math.max(30, resizeStart.height + deltaY);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          break;
        case 'se': // Bottom-right corner - keep top-left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          newHeight = Math.max(30, resizeStart.height + deltaY);
          break;
        case 'n': // Top edge - keep bottom fixed
          newHeight = Math.max(30, resizeStart.height - deltaY);
          newY = resizeStart.elementY + (resizeStart.height - newHeight);
          break;
        case 's': // Bottom edge - keep top fixed
          newHeight = Math.max(30, resizeStart.height + deltaY);
          break;
        case 'w': // Left edge - keep right fixed
          newWidth = Math.max(50, resizeStart.width - deltaX);
          newX = resizeStart.elementX + (resizeStart.width - newWidth);
          break;
        case 'e': // Right edge - keep left fixed
          newWidth = Math.max(50, resizeStart.width + deltaX);
          break;
      }
      
      // Apply boundary constraints during resize
      const constrainedPosition = enforceContentAreaBounds(newX, newY, newWidth, newHeight);
      
      setSize({ width: newWidth, height: newHeight });
      setPosition({ x: constrainedPosition.x, y: constrainedPosition.y });
      setHasBeenMoved(true);
      setIsAbsolutePositioned(true);

      // Notify parent of position and size changes
      if (onPositionChange) {
        onPositionChange({ x: constrainedPosition.x, y: constrainedPosition.y });
      }
      if (onSizeChange) {
        onSizeChange({ width: newWidth, height: newHeight });
      }
    }
  }, [isDragging, isResizing, isEditMode, isPinned, dragStart, resizeStart, size, resizeHandle, hasBeenMoved, enforceContentAreaBounds, onPositionChange, onSizeChange]);

  // Handle mouse up
  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setIsResizing(false);
    setResizeHandle('');
  }, []);

  // Add global event listeners
  useEffect(() => {
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
    
    const elementRect = elementRef.current?.getBoundingClientRect();
    const currentX = elementRect ? elementRect.left : position.x;
    const currentY = elementRect ? elementRect.top : position.y;
    
    setResizeStart({
      x: e.clientX,
      y: e.clientY,
      width: size.width,
      height: size.height,
      elementX: currentX,
      elementY: currentY
    });
  }, [isEditMode, isPinned, size, position]);

  // Toggle edit mode - SIMPLE and CLEAN
  const toggleEditMode = useCallback(() => {
    if (!isEditMode) {
      // Entering edit mode - just set absolute positioning
      setIsAbsolutePositioned(true);
    } else {
      // Exiting edit mode
      setIsDragging(false);
      setIsResizing(false);
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

  // Handle text change
  const handleTextChange = useCallback((newText: string) => {
    setCurrentText(newText);
    if (onTextChange) {
      onTextChange(newText);
    }
  }, [onTextChange]);

  // Toggle text editing - SIMPLE and CLEAN
  const toggleTextEdit = useCallback(() => {
    if (isEditingText) {
      // Finishing edit - just save the text
      const inputElement = elementRef.current?.querySelector('input');
      if (inputElement) {
        setCurrentText(inputElement.value);
      }
    }
    // No size changes - keep it simple
    setIsEditingText(!isEditingText);
  }, [isEditingText]);

  // Handle window resize to update bounds
  useEffect(() => {
    const handleResize = () => {
      // If element is positioned and moved, ensure it stays within bounds
      if (isAbsolutePositioned && hasBeenMoved) {
        const constrainedPosition = enforceContentAreaBounds(
          position.x, 
          position.y, 
          size.width, 
          size.height
        );
        
        // Only update position if it's outside bounds
        if (constrainedPosition.x !== position.x || constrainedPosition.y !== position.y) {
          setPosition(constrainedPosition);
          if (onPositionChange) {
            onPositionChange(constrainedPosition);
          }
        }
      }
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [isAbsolutePositioned, hasBeenMoved, position, size, enforceContentAreaBounds, onPositionChange]);

  // Render resize handles
  const renderResizeHandles = () => {
    if (!isEditMode || isPinned) return null;

    const handleStyle = {
      position: 'absolute' as const,
      width: '8px',
      height: '8px',
      backgroundColor: 'rgba(255, 255, 255, 0.9)',
      border: '1px solid #0f172a',
      zIndex: 10
    };

    return (
      <>
        {/* Corner handles */}
        <div style={{ ...handleStyle, top: '-4px', left: '-4px', cursor: 'nw-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'nw')} />
        <div style={{ ...handleStyle, top: '-4px', right: '-4px', cursor: 'ne-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'ne')} />
        <div style={{ ...handleStyle, bottom: '-4px', left: '-4px', cursor: 'sw-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'sw')} />
        <div style={{ ...handleStyle, bottom: '-4px', right: '-4px', cursor: 'se-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'se')} />
        
        {/* Edge handles */}
        <div style={{ ...handleStyle, top: '-4px', left: '50%', transform: 'translateX(-50%)', cursor: 'n-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'n')} />
        <div style={{ ...handleStyle, bottom: '-4px', left: '50%', transform: 'translateX(-50%)', cursor: 's-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 's')} />
        <div style={{ ...handleStyle, top: '50%', left: '-4px', transform: 'translateY(-50%)', cursor: 'w-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'w')} />
        <div style={{ ...handleStyle, top: '50%', right: '-4px', transform: 'translateY(-50%)', cursor: 'e-resize' }} onMouseDown={(e) => handleResizeMouseDown(e, 'e')} />
      </>
    );
  };

  // Render control buttons
  const renderControlButtons = () => {
    if (!isHovered && !isEditMode) return null;

    const buttonStyle = {
      width: '24px',
      height: '24px',
      borderRadius: '4px',
      border: 'none',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      cursor: 'pointer',
      transition: 'all 0.2s ease',
      boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)',
      zIndex: 10,
      backgroundColor: 'rgba(255, 255, 255, 0.9)'
    };

    return (
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
          style={buttonStyle}
          title={isEditMode ? "Exit edit mode" : "Edit element"}
        >
          {isEditMode ? <Move size={12} color="#dc2626" /> : <Edit3 size={12} color={isEditMode ? "#dc2626" : "#0f172a"} />}
        </button>
        
        {/* Pin Button */}
        <button
          onClick={togglePin}
          style={{
            ...buttonStyle,
            backgroundColor: isPinned ? '#ffffff' : 'rgba(255, 255, 255, 0.9)'
          }}
          title={isPinned ? "Unpin element" : "Pin element"}
        >
          <Pin size={12} color={isPinned ? "#dc2626" : "#0f172a"} />
        </button>

        {/* Text Edit Button (only for buttons with text) */}
        {elementType === 'button' && currentText !== null && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              toggleTextEdit();
            }}
            style={buttonStyle}
            title={isEditingText ? "Finish editing text" : "Edit text"}
          >
            <Type size={12} color={isEditingText ? "#dc2626" : "#0f172a"} />
          </button>
        )}
      </div>
    );
  };

  // Always render the element - no loading state
  console.log('EditableElement rendering:', { isInitialized, currentText, elementType });

  // Simple fallback if something goes wrong
  if (!children) {
    return <div style={{ padding: '20px', backgroundColor: '#f3f4f6', border: '2px dashed #d1d5db' }}>
      No children provided to EditableElement
    </div>;
  }

  return (
    <div
      ref={elementRef}
      style={{
        position: isAbsolutePositioned ? 'absolute' : 'relative',
        left: isAbsolutePositioned ? `${position.x}px` : 'auto',
        top: isAbsolutePositioned ? `${position.y}px` : 'auto',
        width: isAbsolutePositioned && hasBeenMoved ? `${size.width}px` : 'auto',
        height: isAbsolutePositioned && hasBeenMoved ? `${size.height}px` : 'auto',
        border: isEditMode 
          ? '2px dashed rgba(255, 255, 255, 0.8)' 
          : isHovered 
            ? '2px solid rgba(255, 255, 255, 0.3)' 
            : '2px solid transparent',
        transition: isEditMode ? 'none' : 'all 0.2s ease',
        cursor: isEditMode && !isPinned ? 'move' : 'pointer',
        zIndex: isAbsolutePositioned ? 1001 : 'auto',
        display: 'inline-block',
        boxSizing: 'border-box',
        minWidth: 'fit-content',
        minHeight: 'fit-content',
        ...style
      }}
      className={className}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      onMouseDown={handleMouseDown}
    >
      {/* Element Content */}
      <div style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        position: 'relative'
      }}>
        {React.cloneElement(children as React.ReactElement, {
          children: isEditingText && elementType === 'button' ? (
            <input
              type="text"
              value={currentText}
              onChange={(e) => handleTextChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  setIsEditingText(false);
                }
              }}
              style={{
                background: 'transparent',
                border: 'none',
                outline: 'none',
                color: 'inherit',
                fontSize: 'inherit',
                fontWeight: 'inherit',
                fontFamily: 'inherit',
                textAlign: 'center',
                width: '100%',
                height: '100%'
              }}
              autoFocus
            />
          ) : currentText !== null ? currentText : (children as React.ReactElement).props.children
        })}
      </div>

      {/* Resize Handles */}
      {renderResizeHandles()}

      {/* Control Buttons */}
      {renderControlButtons()}
    </div>
  );
};

export default EditableElement;