//
//  main.c
//  2222
//
//  Created by 姚墨杰 on 11/11/14.
//  Copyright (c) 2014 yao. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>

#define STARTNODE	1
#define ENDNODE		2
#define BARRIER		3

typedef struct AStarNode
{
    int s_x;	// 坐标(最终输出路径需要)
    int s_y;
    int s_g;	// 起点到此点的距离( 由g和h可以得到f，此处f省略，f=g+h )
    int	s_h;	// 启发函数预测的此点到终点的距离
    int s_style;// 结点类型：起始点，终点，障碍物
    struct AStarNode * s_parent;	// 父节点
    int s_is_in_closetable;		// 是否在close表中
    int s_is_in_opentable;		// 是否在open表中
}AStarNode, *pAStarNode;

int number = 100;
AStarNode  map_maze[10][10];		// 结点数组
pAStarNode open_table[number];		// open表
pAStarNode close_table[number];		// close表
int   open_node_count;	// open表中节点数量
int	   close_node_count;	// close表中结点数量
pAStarNode path_stack[100];		// 保存路径的栈
int        top = -1;			// 栈顶


// 交换两个元素
//
void swap( int idx1, int idx2 )
{
    pAStarNode tmp = open_table[idx1];
    open_table[idx1] = open_table[idx2];
    open_table[idx2] = tmp;
}


__global__ void cdp_simple_quicksort(int *data,int left,int right)
{
    
    
    unsigned int *lptr = data+left;
    unsigned int *rptr = data+right;
    unsigned int  pivot = data[(left+right)/2];
    
    // Do the partitioning.
    while(lptr <= rptr)
    {
        // Find the next left- and right-hand values to swap
        unsigned int lval = *lptr;
        unsigned int rval = *rptr;
        
        // Move the left pointer as long as the pointed element is smaller than the pivot.
        while( lval < pivot )
        {
            lptr++;
            lval = *lptr;
        }
        
        // Move the right pointer as long as the pointed element is larger than the pivot.
        while( rval > pivot )
        {
            rptr--;
            rval = *rptr;
        }
        
        // If the swap points are valid, do the swap!
        if(lptr <= rptr)
        {
            *lptr++ = rval;
            *rptr-- = lval;
        }
    }
    
    // Now the recursive part
    int nright = rptr - data;
    int nleft  = lptr - data;
    
    // Launch a new block to sort the left part.
    if(left < (rptr-data))
    {
        cudaStream_t s;
        cudaStreamCreateWithFlags( &s, cudaStreamNonBlocking );
        cdp_simple_quicksort<<< 1, 1, 0, s >>>(data, left, nright);
        cudaStreamDestroy( s );
    }
    
    // Launch a new block to sort the right part.
    if((lptr-data) < right)
    {
        cudaStream_t s1;
        cudaStreamCreateWithFlags( &s1, cudaStreamNonBlocking );
        cdp_simple_quicksort<<< 1, 1, 0, s1 >>>(data, nleft, right);
        cudaStreamDestroy( s1 );
    }
}

void run_qsort(unsigned int *data)
{
    
    int left = 0;
    int right = number-1;
    cdp_simple_quicksort<<< 1, 1 >>>(data, left, right);
    
    cudaDeviceSynchronize();
}


// 判断邻居点是否可以进入open表
//
void insert_to_opentable( int x, int y, pAStarNode curr_node, pAStarNode end_node, int w )
{
    int i;
    
    if ( map_maze[x][y].s_style != BARRIER )		// 不是障碍物
    {
        if ( !map_maze[x][y].s_is_in_closetable )	// 不在闭表中
        {
            if ( map_maze[x][y].s_is_in_opentable )	// 在open表中
            {
                // 需要判断是否是一条更优化的路径
                //
                if ( map_maze[x][y].s_g > curr_node->s_g + w )	// 如果更优化
                {
                    map_maze[x][y].s_g = curr_node->s_g + w;     //把优化后的只赋给路径
                    map_maze[x][y].s_parent = curr_node;         //父节点
                    
                    for ( i = 0; i < open_node_count; ++i )
                    {
                        if ( open_table[i]->s_x == map_maze[x][y].s_x && open_table[i]->s_y == map_maze[x][y].s_y )
                        {
                            break;
                        }
                    }
                    
                    adjust_heap( i );					// 下面调整点
                }
            }
            else									// 不在open中
            {
                map_maze[x][y].s_g = curr_node->s_g + w;
                map_maze[x][y].s_h = abs(end_node->s_x - x ) + abs(end_node->s_y - y);
                map_maze[x][y].s_parent = curr_node;
                map_maze[x][y].s_is_in_opentable = 1;
                open_table[open_node_count++] = &(map_maze[x][y]);
            }
        }
    }
}

// 查找邻居
// 对上下左右8个邻居进行查找
//
void get_neighbors( pAStarNode curr_node, pAStarNode end_node )
{
    int x = curr_node->s_x;
    int y = curr_node->s_y;
    
    // 下面对于8个邻居进行处理！
    //
    if ( ( x + 1 ) >= 0 && ( x + 1 ) < 10 && y >= 0 && y < 10 )
    {
        insert_to_opentable( x+1, y, curr_node, end_node, 10 );
    }
    
    if ( ( x - 1 ) >= 0 && ( x - 1 ) < 10 && y >= 0 && y < 10 )
    {
        insert_to_opentable( x-1, y, curr_node, end_node, 10 );
    }
    
    if ( x >= 0 && x < 10 && ( y + 1 ) >= 0 && ( y + 1 ) < 10 )
    {
        insert_to_opentable( x, y+1, curr_node, end_node, 10 );
    }
    
    if ( x >= 0 && x < 10 && ( y - 1 ) >= 0 && ( y - 1 ) < 10 )
    {
        insert_to_opentable( x, y-1, curr_node, end_node, 10 );
    }
    
    if ( ( x + 1 ) >= 0 && ( x + 1 ) < 10 && ( y + 1 ) >= 0 && ( y + 1 ) < 10 )
    {
        insert_to_opentable( x+1, y+1, curr_node, end_node, 14 );
    }
    
    if ( ( x + 1 ) >= 0 && ( x + 1 ) < 10 && ( y - 1 ) >= 0 && ( y - 1 ) < 10 )
    {
        insert_to_opentable( x+1, y-1, curr_node, end_node, 14 );
    }
    
    if ( ( x - 1 ) >= 0 && ( x - 1 ) < 10 && ( y + 1 ) >= 0 && ( y + 1 ) < 10 )
    {
        insert_to_opentable( x-1, y+1, curr_node, end_node, 14 );
    }
    
    if ( ( x - 1 ) >= 0 && ( x - 1 ) < 10 && ( y - 1 ) >= 0 && ( y - 1 ) < 10 )
    {
        insert_to_opentable( x-1, y-1, curr_node, end_node, 14 );
    }
}


int main()
{
    // 地图数组的定义
    //
    int *d_data = 0;
    cudaMalloc((void **)&d_data, number * sizeof(unsigned int));
    AStarNode *start_node;			// 起始点
    AStarNode *end_node;			// 结束点
    AStarNode *curr_node;			// 当前点
    int       is_found;			// 是否找到路径
    int maze[][10] ={			// 仅仅为了好赋值给map_maze
        { 1,0,0,3,0,3,0,0,0,0 },
        { 0,0,3,0,0,3,0,3,0,3 },
        { 3,0,0,0,0,3,3,3,0,3 },
        { 3,0,3,0,0,0,0,0,0,3 },
        { 3,0,0,0,0,3,0,0,0,3 },
        { 3,0,0,3,0,0,0,3,0,3 },
        { 3,0,0,0,0,3,3,0,0,0 },
        { 0,0,2,0,0,0,0,0,0,0 },
        { 3,3,3,0,0,3,0,3,0,3 },
        { 3,0,0,0,0,3,3,3,0,3 },
    };
    int		  i,j,x;
    
    // 下面准备点
    //
    for( i = 0; i < 10; ++i )
    {
        for ( j = 0; j < 10; ++j )
        {
            map_maze[i][j].s_g = 0;
            map_maze[i][j].s_h = 0;
            map_maze[i][j].s_is_in_closetable = 0;
            map_maze[i][j].s_is_in_opentable = 0;
            map_maze[i][j].s_style = maze[i][j];
            map_maze[i][j].s_x = i;
            map_maze[i][j].s_y = j;
            map_maze[i][j].s_parent = NULL;
            
            if ( map_maze[i][j].s_style == STARTNODE )	// 起点
            {
                start_node = &(map_maze[i][j]);
            }
            else if( map_maze[i][j].s_style == ENDNODE )	// 终点
            {
                end_node = &(map_maze[i][j]);
            }
            
            printf("%d ", maze[i][j]);
        }
        
        printf("\n");
    }
    
    // 下面使用A*算法得到路径
    //
    open_table[open_node_count++] = start_node;			// 起始点加入open表
    
    start_node->s_is_in_opentable = 1;				// 加入open表
    start_node->s_g = 0;
    start_node->s_h = abs(end_node->s_x - start_node->s_x) + abs(end_node->s_y - start_node->s_y);
    start_node->s_parent = NULL;
    
    if ( start_node->s_x == end_node->s_x && start_node->s_y == end_node->s_y )
    {
        printf("起点==终点！\n");
        return 0;
    }
    
    is_found = 0;
    
    while( 1 )
    {
        curr_node = open_table[0];		// open表的第一个点一定是f值最小的点(通过堆排序得到的)
        open_table[0] = open_table[--open_node_count];	// 最后一个点放到第一个点，然后进行堆调整
        
        printf("0\n");
        cudaMemcpy(d_data, open_table, number * sizeof(int), cudaMemcpyHostToDevice);
        run_qsort(d_data,);
        cudaMemcpy(open_table, d_data, number * sizeof(int), cudaMemcpyDeviceToHost);
        printf("1\n");
        //adjust_heap( 0 );				// 调整堆
        
        close_table[close_node_count++] = curr_node;	// 当前点加入close表
        curr_node->s_is_in_closetable = 1;		// 已经在close表中了
        maze[curr_node->s_x][curr_node->s_y] = 8;
        
        if ( curr_node->s_x == end_node->s_x && curr_node->s_y == end_node->s_y )// 终点在close中，结束
        {
            is_found = 1;
            break;
        }
        
        get_neighbors( curr_node, end_node );			// 对邻居的处理
        
        if ( open_node_count == 0 )				// 没有路径到达
        {
            is_found = 0;
            break;
        }
    }
    
    if ( is_found )
    {
        curr_node = end_node;
        
        while( curr_node )
        {
            path_stack[++top] = curr_node;
            curr_node = curr_node->s_parent;
        }
        
        while( top >= 0 )		// 下面是输出路径看看~
        {
            if ( top > 0 )
            {
                printf("(%d,%d)-->", path_stack[top]->s_x, path_stack[top--]->s_y);
            }
            else
            {
                printf("(%d,%d)", path_stack[top]->s_x, path_stack[top--]->s_y);
            }
        }
    }
    else
    {
        printf("么有找到路径");
    }
    
    puts("");
    
    
    for( i = 0; i < 10; ++i )
    {
        for ( j = 0; j < 10; ++j )
        {
            printf("%d ", maze[i][j]);
        }
        
        printf("\n");
    }
    cudaFree(d_data);
    return 0;
}






