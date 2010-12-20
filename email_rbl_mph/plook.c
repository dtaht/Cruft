#include <cmph.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/fcntl.h>
#include <string.h>
#include <errno.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/mman.h>
#include <sys/stat.h>

// ALL THESE ARE DEPRECATED!  Use inet_pton()  or inet_ntop() instead for ipv6

/* char *inet_ntoa(struct in_addr in);
int inet_aton(const char *cp, struct in_addr *inp);
in_addr_t inet_addr(const char *cp); */

// Create minimal perfect hash function from in-disk keys using BDZ algorithm

struct cmph_hash_obj { 
  char *keyfile;
  FILE *keys_fd;
  int algo;
  cmph_io_adapter_t *source;
  cmph_config_t *config;
  cmph_t *hash;
} ;

unsigned int convert_textfile_to_ip4_bin(char *textfile) {
  char line[255];
  in_addr_t v;
  int count = 0;
  int err = 0;
  int white = 0;
  FILE *fp = fopen(textfile,"r"); 
  sprintf(line,"%s.bin",textfile);
  FILE *bp = fopen(line,"w");

  if(fp != NULL) {
    if(bp != NULL) {
      //      "%[0-9.]"
      err = fscanf(fp,"%[0-9.]",line);
      while(err > 0 && err != EOF) {
	v = inet_addr(line);
	fwrite(&v,4,1,bp);
	count++;
	white = fgetc(fp); // FIXME chomp shitespace better
	err = fscanf(fp,"%[0-9.]",line);
	if(count > (1024*1024*4)) {
	  fprintf(stderr,"OOPS, infinite loop\n");
	  return(0);
	}
     }	
      fflush(bp);
      fclose(bp);
    }
    fclose(fp);
  }

  return(count);
}

struct mapfile {
  int fp;
  void *map;
  struct stat s;
};

size_t fmmap_ip_rw(struct mapfile *p, char *binfile) {
  p->fp = open(binfile,O_RDWR); 
  fstat(p->fp,&(p->s));
  if(p->fp > 0) {
    p->map = mmap(NULL,p->s.st_size,PROT_READ|PROT_WRITE,MAP_SHARED,p->fp,0);
  }
  return(p->s.st_size);
}


size_t fmmap_ip(struct mapfile *p, char *binfile) {
  p->fp = open(binfile,O_RDONLY); 
  fstat(p->fp,&(p->s));
  if(p->fp > 0) {
    p->map = mmap(NULL,p->s.st_size,PROT_READ,MAP_SHARED,p->fp,0);
  }
  return(p->s.st_size);
}

int unmap_ip(struct mapfile *p) {
  if(p->map != NULL) munmap(p->map,p->s.st_size);
  if(p->fp > 0) close(p->fp);
  return(0);
}

int walk_ips(struct mapfile *p) {
  struct in_addr *ip = (struct in_addr *) p->map;
  unsigned i;
  for(i = 0; i < (p->s.st_size)/sizeof(int); i++) {
    printf("%s\n", inet_ntoa((ip[i]))); 
  }
  return(0);
}

/*
cmph_uint32 cmph_size(cmph_t *mphf);
void cmph_destroy(cmph_t *mphf);

// Hash serialization/deserialization 
int cmph_dump(cmph_t *mphf, FILE *f);
cmph_t *cmph_load(FILE *f);

*/

/** \fn void cmph_pack(cmph_t *mphf, void *packed_mphf);
 *  \brief Support the ability to pack a perfect hash function into a preallocated contiguous memory space pointed by packed_mphf.
 *  \param mphf pointer to the resulting mphf
 *  \param packed_mphf pointer to the contiguous memory area used to store the
 *  \param resulting mphf. The size of packed_mphf must be at least cmph_packed_size()
 */

/* void cmph_pack(cmph_t *mphf, void *packed_mphf); */

/** \fn cmph_uint32 cmph_packed_size(cmph_t *mphf);
 *  \brief Return the amount of space needed to pack mphf.
 *  \param mphf pointer to a mphf
 *  \return the size of the packed function or zero for failures
 */

/* cmph_uint32 cmph_packed_size(cmph_t *mphf); */

/** cmph_uint32 cmph_search(void *packed_mphf, const char *key, cmph_uint32 keylen);
 *  \brief Use the packed mphf to do a search.
 *  \param  packed_mphf pointer to the packed mphf
 *  \param key key to be hashed
 *  \param keylen key legth in bytes
 *  \return The mphf value
 */

/*
cmph_uint32 cmph_search_packed(void *packed_mphf, const char *key, cmph_uint32 keylen);
*/

int create_disk_hash(struct cmph_hash_obj *o) {
  char mphfile[1024];
  FILE *mph;
  int count = 0;

  o->keys_fd = fopen(o->keyfile, "r");
  if (o->keys_fd == NULL)
    {
      fprintf(stderr, "File %s not found\n", o->keyfile);
      return(-1);
    }
  if((count = convert_textfile_to_ip4_bin(o->keyfile)) > 0) {
    fprintf(stderr,"binary file dumped\n");
  }
      
  o->source = cmph_io_nlfile_adapter(o->keys_fd);
  o->config = cmph_config_new(o->source);
  // cmph_config_set_algo(o->config, CMPH_CHM);
  cmph_config_set_algo(o->config, CMPH_BDZ); // seems like a win
  o->hash = cmph_new(o->config);
  sprintf(mphfile,"%s.mph",o->keyfile);
  mph = fopen(mphfile, "w+");
  if (mph == NULL)
    {
      fprintf(stderr, "File %s not found\n",mphfile);
      return(1);
    } else {
    cmph_dump(o->hash, mph);
    pack_n_save(o,"backup.mph");
    fclose(mph);
  }
  cmph_config_destroy(o->config);
  return (0);
}

int open_disk_hash(struct cmph_hash_obj *o) {
  char mphfile[1024];
  FILE *mph;
  sprintf(mphfile,"%s.mph",o->keyfile);
  o->keys_fd = fopen(mphfile, "r");
  if (o->keys_fd == NULL)
    {
      fprintf(stderr, "File %s not found\n", mphfile);
      return(1);
    }
  o->hash = cmph_load(o->keys_fd);
  return (0);
}

// FIXME See if there is a hashfile with a later mod time

int create_or_open_disk_hash(struct cmph_hash_obj *o) {
  char dbfile[1024];
  sprintf(dbfile, "%s.mph",o->keyfile); 
  if(!access(dbfile,F_OK)) {
    fprintf(stderr,"opening prexisting hash\n");
    return(open_disk_hash(o));
  } else {
    return(create_disk_hash(o));
  }
}

int lookup_key(struct cmph_hash_obj *o,char *key) {
  return(cmph_search(o->hash, key, (cmph_uint32)strlen(key)));
}

int int_cmp(const void *a, const void *b) 
{ 
    const int *ia = (const int *)a; // casting pointer types 
    const int *ib = (const int *)b;
    return *ia  - *ib; 
	/* integer comparison: returns negative if b > a 
	and positive if a > b */ 
} 



// So we can readonly mmap a packed_mphf
// pmph

// PROT_READ, MAP_SHARED
// #include <sys/mman.h>
// void *mmap(void *start, size_t length, int prot, int flags,           int
// fd, off_t offset);
// int munmap(void *start, size_t length);


int pack_n_save(struct cmph_hash_obj *o, char *filename) {
  size_t size;
  int fp = open(filename,O_RDWR|O_CREAT);
  if(fp > 0) {
    void *p = malloc(size = cmph_packed_size(o->hash));
    if(p !=NULL) {
      cmph_pack(o->hash, p);
      write(fp,p,size);
      free(p);
    }
    close(fp);
  } 
}

/* 
   What we need is an opaque structure for a transformation
   callback. Maybe

int lookup_key_crossref(struct cmph_hash_obj *o,char *key) {
  int k = cmph_search(o->hash, key, (cmph_uint32)strlen(key));
  if(o->ref[k] == key) { 
  } else {
    return(-1);
  }
}
*/

int parse_config(int argc, char **argv, struct cmph_hash_obj *o) {
}

int closeit(struct cmph_hash_obj *o) {
  //  if(o->hash) cmph_destroy(o->hash);
  // if(o->source) cmph_io_nlfile_adapter_destroy(o->source);
  // if(o->keys_fd) fclose(o->keys_fd);
}

int main(int argc, char **argv)
{
  struct cmph_hash_obj o;
  o.keyfile = "keys.txt";
  const char *key = "1.11.145.30";
  struct mapfile ip_map;
  int err;

  if (!(err = create_or_open_disk_hash(&o))) {
    fmmap_ip_rw(&ip_map,"keys.txt.bin");
    qsort(ip_map.map,ip_map.s.st_size/4, 4, int_cmp);
    walk_ips(&ip_map);

    unsigned int id = cmph_search(o.hash, key, (cmph_uint32)strlen(key));
    fprintf(stderr, "Id:%u\n", id);
    id = cmph_search(o.hash, "192.168.176.1", (cmph_uint32)strlen("192.168.176.1"));
    fprintf(stderr, "Invalid Id:%u\n", id);
    closeit(&o);
  } else {
    fprintf(stderr, "Cannot create hash, err %d, errno %d\n", err, errno);
  }
  return 0;
}
