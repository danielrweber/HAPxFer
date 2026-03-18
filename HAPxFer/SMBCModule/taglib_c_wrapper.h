//
//  taglib_c_wrapper.h
//  HAPxFer
//
//  Minimal declarations for TagLib's C API functions used by MetadataService.
//  CXXTagLib links statically via SPM, providing the implementations.
//

#ifndef taglib_c_wrapper_h
#define taglib_c_wrapper_h

#ifndef BOOL
#define BOOL int
#endif

// Opaque types
typedef struct { int dummy; } TagLib_File;
typedef struct { int dummy; } TagLib_Tag;

// File operations
extern TagLib_File *taglib_file_new(const char *filename);
extern void taglib_file_free(TagLib_File *file);
extern BOOL taglib_file_is_valid(const TagLib_File *file);
extern BOOL taglib_file_save(TagLib_File *file);

// Tag access
extern TagLib_Tag *taglib_file_tag(const TagLib_File *file);

// Tag getters (return UTF-8 strings)
extern char *taglib_tag_artist(const TagLib_Tag *tag);

// Tag setters (accept UTF-8 strings)
extern void taglib_tag_set_artist(TagLib_Tag *tag, const char *artist);

// String management
extern void taglib_set_strings_unicode(BOOL unicode);
extern void taglib_tag_free_strings(void);

#endif /* taglib_c_wrapper_h */
